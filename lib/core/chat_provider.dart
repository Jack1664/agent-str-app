import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:hex/hex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/friend.dart';
import '../models/wallet.dart';
import 'app_badge_service.dart';
import 'crypto_util.dart';
import 'db_helper.dart';
import 'notification_service.dart';
import '../ui/widgets/top_notice.dart';

/// 表示收到的好友申请
class FriendRequest {
  final String senderPubKey; // 发送者公钥
  final String content; // 申请内容
  final int timestamp; // 时间戳

  FriendRequest({
    required this.senderPubKey,
    required this.content,
    required this.timestamp,
  });
}

/// 话题/群组信息
class TopicInfo {
  final String id;
  final String title;
  String alias; // 用户自定义的话题别名
  bool isSubscribed;

  TopicInfo({
    required this.id,
    required this.title,
    String? alias,
    this.isSubscribed = false,
  }) : this.alias = alias ?? title;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'alias': alias,
    'isSubscribed': isSubscribed,
  };

  factory TopicInfo.fromJson(Map<String, dynamic> json) => TopicInfo(
    id: json['id'],
    title: json['title'],
    alias: json['alias'],
    isSubscribed: json['isSubscribed'] ?? false,
  );
}

/// 聊天与通信核心提供者，负责 WebSocket 连接、消息收发及好友管理
class ChatProvider with ChangeNotifier {
  static const String defaultRelayUrl = 'ws://112.126.60.140:8765/ws/agent';

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isAuthenticated = false;
  bool _isConnecting = false;

  List<String> _discoveredTopics = []; // 从服务器发现的话题 ID 列表
  List<TopicInfo> _myTopics = []; // 我订阅的话题列表
  List<Friend> _friends = [];
  Map<String, List<ChatMessage>> _messages = {};
  Map<String, int> _unreadCounts = {};
  List<FriendRequest> _pendingRequests = []; // 待处理的好友申请
  String? _activeChatId;

  // 认证流程相关变量
  Map<String, dynamic>? _lastChallenge;
  Completer<bool>? _authCompleter;
  ed.PrivateKey? _activePrivateKey;

  // 连接 management
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _lastUsedUrl;
  String? _lastDirectPeerId;
  String _agentsUrl = 'http://112.126.60.140:8765/api/agents';
  String _topicsUrl = 'http://112.126.60.140:8765/api/topics';
  Wallet? _lastUsedWallet;

  // --- Getters ---
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  bool get isConnecting => _isConnecting;
  bool get isAuthPending => _lastChallenge != null && !_isAuthenticated;
  Map<String, dynamic>? get lastChallenge => _lastChallenge;

  String get lastUsedUrl => _lastUsedUrl ?? defaultRelayUrl;
  String get agentsUrl => _agentsUrl;
  String get topicsUrl => _topicsUrl;
  Wallet? get lastUsedWallet => _lastUsedWallet;

  ed.PrivateKey? get activePrivateKey => _activePrivateKey;

  List<String> get discoveredTopics => _discoveredTopics;
  List<TopicInfo> get myTopics => _myTopics;
  List<Friend> get friends => _friends;
  Map<String, List<ChatMessage>> get messages => _messages;
  Map<String, int> get unreadCounts => _unreadCounts;
  List<FriendRequest> get pendingRequests => _pendingRequests;
  int get totalUnreadCount =>
      _unreadCounts.values.fold(0, (sum, count) => sum + count);

  static const String _relayUrlKeyPrefix = 'relay_url_';
  static const String _agentsUrlKeyPrefix = 'agents_url_';
  static const String _topicsUrlKeyPrefix = 'topics_url_';
  static const String _friendsKeyPrefix = 'friends_v2_';
  static const String _topicsKeyPrefix = 'my_topics_v2_';
  static const String _unreadCountsKeyPrefix = 'unread_counts_v1_';

  int unreadCountFor(String peerId) => _unreadCounts[peerId] ?? 0;

  Future<void> _syncAppBadge() async {
    final total = totalUnreadCount;
    if (total <= 0) {
      await AppBadgeService.clear();
      return;
    }
    await AppBadgeService.updateCount(total);
  }

  void setActiveChat(String? peerId) {
    final wasChanged = _activeChatId != peerId;
    _activeChatId = peerId;
    if (peerId != null) {
      markChatRead(peerId, notify: false);
    }
    if (wasChanged) {
      notifyListeners();
    }
  }

  void markChatRead(String peerId, {bool notify = true}) {
    if (_unreadCounts.remove(peerId) != null) {
      final agentId = _lastUsedWallet?.agentId;
      if (agentId != null) {
        unawaited(_saveUnreadCounts(agentId));
      }
      unawaited(_syncAppBadge());
      if (notify) {
        notifyListeners();
      }
    }
  }

  /// 连接到指定的 Relay 服务器
  Future<void> connect(String url, Wallet activeWallet) async {
    final normalizedUrl = url.trim().replaceFirst(RegExp(r'/*$'), '');
    if (_isConnected &&
        !_isConnecting &&
        _lastUsedWallet?.agentId == activeWallet.agentId &&
        _lastUsedUrl == normalizedUrl) {
      return;
    }

    if (_isConnecting &&
        _lastUsedUrl == url &&
        _lastUsedWallet?.agentId == activeWallet.agentId)
      return;

    // 如果已经在连接其他钱包，先断开
    if (_isConnected && _lastUsedWallet?.agentId != activeWallet.agentId) {
      _channel?.sink.close();
      _isConnected = false;
      _isAuthenticated = false;
    }

    // 格式化 URL
    String targetUrl = url.trim();
    while (targetUrl.endsWith('/')) {
      targetUrl = targetUrl.substring(0, targetUrl.length - 1);
    }
    _lastUsedUrl = targetUrl;
    _lastUsedWallet = activeWallet;
    _isConnecting = true;
    _isConnected = false;
    _isAuthenticated = false;
    _activePrivateKey = null; // 重置私钥，等待重新派生
    notifyListeners();

    try {
      debugPrint("正在尝试连接: $targetUrl");

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..badCertificateCallback = (cert, host, port) => true;

      final WebSocket webSocket = await WebSocket.connect(
        targetUrl,
        customClient: client,
      ).timeout(const Duration(seconds: 15));

      _channel = IOWebSocketChannel(webSocket);

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _lastChallenge = null;
      notifyListeners();

      TopNotice.show(
        'Connected for ${activeWallet.name}',
        backgroundColor: Colors.green,
      );

      _channel!.stream.listen(
        (rawData) {
          debugPrint("收到原始数据: $rawData");
          _handleRawMessage(rawData, activeWallet);
        },
        onDone: () {
          _handleDisconnect("Relay connection closed");
          _scheduleReconnect();
        },
        onError: (e) {
          debugPrint("WS 流错误: $e");
          _handleDisconnect("Network Error: $e");
          _scheduleReconnect();
        },
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${_relayUrlKeyPrefix}${activeWallet.agentId}',
        url,
      );
      await loadFriends(activeWallet.agentId);
      await _loadMyTopics(activeWallet.agentId);
    } catch (e) {
      debugPrint("连接失败: $e");
      _isConnecting = false;
      _handleDisconnect("Connect Failed: $e");
      _scheduleReconnect();
    }
  }

  /// 安排自动重连
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_lastUsedUrl == null || _lastUsedWallet == null) return;

    _reconnectAttempts++;
    int delay = (1 << _reconnectAttempts).clamp(2, 30); // 指数退避算法

    debugPrint("$delay 秒后尝试重连...");
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_isConnected && !_isConnecting) {
        connect(_lastUsedUrl!, _lastUsedWallet!);
      }
    });
  }

  /// 处理从 WebSocket 接收到的原始 JSON 数据
  void _handleRawMessage(dynamic rawData, Wallet activeWallet) {
    try {
      final data = jsonDecode(rawData);
      final type = data['type'];

      if (type == 'challenge') {
        _lastChallenge = data;
        _autoAuthenticate(activeWallet);
        notifyListeners();
      } else if (type == 'connected') {
        _isAuthenticated = true;
        _lastChallenge = null;
        _authCompleter?.complete(true);
        _authCompleter = null;
        notifyListeners();
      } else if (type == 'deliver') {
        _handleDeliver(data, activeWallet);
      } else if (type == 'error') {
        _authCompleter?.complete(false);
        _authCompleter = null;
        final errorMessage = (data['error'] ?? data['message'] ?? data)
            .toString();
        if (errorMessage == 'acl deny' && _lastDirectPeerId != null) {
          _appendSystemMessage(
            _lastDirectPeerId!,
            'Friend request not accepted',
          );
        } else {
          TopNotice.show(
            'Relay error: $errorMessage',
            backgroundColor: Colors.redAccent,
          );
        }
      }
    } catch (e) {
      debugPrint('消息解析错误: $e');
    }
  }

  Future<void> _autoAuthenticate(Wallet activeWallet) async {
    if (_lastChallenge == null) return;
    if (_activePrivateKey == null) {
      final seed = Uint8List.fromList(HEX.decode(activeWallet.seedHex));
      _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }
    final challengeStr =
        "AUTH|${_lastChallenge!['nonce']}|${_lastChallenge!['ts']}";
    final sig = CryptoUtil.signB64(_activePrivateKey!, challengeStr);
    final authPacket = {
      "type": "auth",
      "agent_id": activeWallet.agentId,
      "sig": sig,
    };
    _channel!.sink.add(jsonEncode(authPacket));
  }

  Future<void> _handleDeliver(
    Map<String, dynamic> data,
    Wallet activeWallet,
  ) async {
    final event = data['event'];
    final sender = event['from'];
    final sig = data['sig'];

    final payload = CryptoUtil.canonicalEventPayload(event);
    final isValid = CryptoUtil.verifySignature(payload, sig, sender);
    if (!isValid) return;

    _sendAck(activeWallet.agentId, event);

    if (event['kind'] == 'friend_request') {
      if (!_friends.any((f) => f.pubKeyHex == sender)) {
        if (!_pendingRequests.any((r) => r.senderPubKey == sender)) {
          _pendingRequests.add(
            FriendRequest(
              senderPubKey: sender,
              content: event['content'],
              timestamp: event['created_at'] * 1000,
            ),
          );
          notifyListeners();
        }
      }
    }

    if (event['kind'] == 'message' || event['kind'] == 'friend_request') {
      final chatId = event['chat']['id'];
      final chatType = event['chat']['type'];
      String peerId = sender;
      if (chatType == 'topic') {
        peerId = chatId;
      } else if (sender == activeWallet.agentId) {
        final parts = chatId.split(':');
        if (parts.length == 3 && parts[0] == 'dm') {
          peerId = (parts[1] == sender) ? parts[2] : parts[1];
        }
      }

      if (_messages.containsKey(peerId) &&
          _messages[peerId]!.any((m) => m.signature == sig))
        return;

      final attachments = await _prepareIncomingAttachments(
        event['attachments'] is List ? event['attachments'] as List : const [],
        event['id'] as String? ?? '${event['created_at']}_${sender.hashCode}',
      );
      final metadata = _prepareIncomingMetadata(
        event['metadata'] is Map<String, dynamic>
            ? event['metadata'] as Map<String, dynamic>
            : const {},
        attachments,
      );

      final msg = ChatMessage(
        content: event['content'],
        signature: sig ?? '',
        senderPubKeyHex: sender,
        timestamp: event['created_at'] * 1000,
        isMine: sender == activeWallet.agentId,
        contentType: event['content_type'] as String? ?? 'text/plain',
        metadata: metadata,
        attachments: attachments,
      );

      await DbHelper.insertMessage(activeWallet.agentId, peerId, msg);

      if (!_messages.containsKey(peerId)) _messages[peerId] = [];
      _messages[peerId]!.add(msg);
      if (sender != activeWallet.agentId && event['kind'] == 'message') {
        final shouldMarkUnread =
            _activeChatId != peerId || !NotificationService.isAppInForeground;
        if (shouldMarkUnread) {
          _unreadCounts[peerId] = unreadCountFor(peerId) + 1;
          await _saveUnreadCounts(activeWallet.agentId);
          await _syncAppBadge();
        }
        final notificationTitle = _notificationTitleForMessage(
          chatType,
          peerId,
        );
        await NotificationService.showIncomingMessage(
          title: notificationTitle,
          body: _notificationBodyForMessage(msg),
          badgeCount: totalUnreadCount,
          payload: jsonEncode({
            'chat_type': chatType,
            'peer_id': peerId,
            'title': notificationTitle,
          }),
        );
      }
      notifyListeners();
    }
  }

  String _notificationTitleForMessage(String chatType, String peerId) {
    if (chatType == 'topic') {
      final topic = _myTopics.cast<TopicInfo?>().firstWhere(
        (item) => item?.id == peerId,
        orElse: () => null,
      );
      return topic?.alias.isNotEmpty == true ? topic!.alias : peerId;
    }

    final friend = _friends.cast<Friend?>().firstWhere(
      (item) => item?.pubKeyHex == peerId,
      orElse: () => null,
    );
    return friend?.alias.isNotEmpty == true ? friend!.alias : 'New message';
  }

  String _notificationBodyForMessage(ChatMessage message) {
    if (message.isVoiceMessage) return '[Voice message]';
    if (message.isImageMessage) return '[Image]';
    return message.content;
  }

  void _sendAck(String agentId, Map<String, dynamic> sourceEvent) {
    if (_activePrivateKey == null && _lastUsedWallet != null) {
      final seed = Uint8List.fromList(HEX.decode(_lastUsedWallet!.seedHex));
      _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }
    if (_activePrivateKey == null) return;
    final ackEvent = CryptoUtil.buildEvent(
      agentId: agentId,
      chat: sourceEvent['chat'],
      kind: "ack",
      content: sourceEvent['id'],
    );
    final payload = CryptoUtil.canonicalEventPayload(ackEvent);
    final sig = CryptoUtil.signB64(_activePrivateKey!, payload);
    final packet = {"type": "event", "event": ackEvent, "sig": sig};
    _channel!.sink.add(jsonEncode(packet));
  }

  void _appendSystemMessage(String peerId, String content) {
    final existingMessages = _messages[peerId];
    if (existingMessages != null &&
        existingMessages.isNotEmpty &&
        existingMessages.last.isSystem &&
        existingMessages.last.content == content) {
      return;
    }

    final msg = ChatMessage(
      content: content,
      signature: 'system_${DateTime.now().microsecondsSinceEpoch}',
      senderPubKeyHex: 'system',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSystem: true,
    );
    _messages.putIfAbsent(peerId, () => []);
    _messages[peerId]!.add(msg);
    notifyListeners();
  }

  Future<void> autoConnect(Wallet activeWallet) async {
    if (_isConnected &&
        !_isConnecting &&
        _lastUsedWallet?.agentId == activeWallet.agentId) {
      return;
    }

    _lastUsedWallet = activeWallet;
    // 重置内存状态，准备加载新钱包数据
    _friends = [];
    _myTopics = [];
    _messages = {};
    _unreadCounts = {};
    _pendingRequests = [];
    _activeChatId = null;

    final prefs = await SharedPreferences.getInstance();
    _agentsUrl =
        prefs.getString('${_agentsUrlKeyPrefix}${activeWallet.agentId}') ??
        'http://112.126.60.140:8765/api/agents';
    _topicsUrl =
        prefs.getString('${_topicsUrlKeyPrefix}${activeWallet.agentId}') ??
        'http://112.126.60.140:8765/api/topics';

    await loadFriends(activeWallet.agentId);
    await _loadMyTopics(activeWallet.agentId);
    await _loadUnreadCounts(activeWallet.agentId);
    await _syncAppBadge();
    notifyListeners();

    final savedUrl = prefs.getString(
      '${_relayUrlKeyPrefix}${activeWallet.agentId}',
    );
    final relayUrl = (savedUrl != null && savedUrl.isNotEmpty)
        ? savedUrl
        : defaultRelayUrl;
    if (relayUrl.isNotEmpty) {
      await connect(relayUrl, activeWallet);
    }
  }

  Future<void> updateExploreUrls(
    String agentId,
    String agentsUrl,
    String topicsUrl,
  ) async {
    _agentsUrl = agentsUrl;
    _topicsUrl = topicsUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_agentsUrlKeyPrefix}$agentId', agentsUrl);
    await prefs.setString('${_topicsUrlKeyPrefix}$agentId', topicsUrl);
    notifyListeners();
  }

  Future<void> loadFriends(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? friendsJson = prefs.getString('${_friendsKeyPrefix}$agentId');
    if (friendsJson != null) {
      final List<dynamic> decoded = jsonDecode(friendsJson);
      _friends = decoded.map((e) => Friend.fromJson(e)).toList();
      for (var friend in _friends) {
        _messages[friend.pubKeyHex] = await DbHelper.getMessages(
          agentId,
          friend.pubKeyHex,
        );
      }
    }
    notifyListeners();
  }

  Future<void> _loadMyTopics(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? topicsJson = prefs.getString('${_topicsKeyPrefix}$agentId');
    if (topicsJson != null) {
      final List<dynamic> decoded = jsonDecode(topicsJson);
      _myTopics = decoded.map((e) => TopicInfo.fromJson(e)).toList();
      for (var topic in _myTopics) {
        _messages[topic.id] = await DbHelper.getMessages(agentId, topic.id);
      }
    }
    notifyListeners();
  }

  Future<void> _saveFriends(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_friends.map((e) => e.toJson()).toList());
    await prefs.setString('${_friendsKeyPrefix}$agentId', encoded);
  }

  Future<void> _saveMyTopics(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(
      _myTopics.map((e) => e.toJson()).toList(),
    );
    await prefs.setString('${_topicsKeyPrefix}$agentId', encoded);
  }

  Future<void> _loadUnreadCounts(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final unreadJson = prefs.getString('$_unreadCountsKeyPrefix$agentId');
    if (unreadJson == null || unreadJson.isEmpty) {
      _unreadCounts = {};
      return;
    }

    final decoded = jsonDecode(unreadJson);
    if (decoded is! Map) {
      _unreadCounts = {};
      return;
    }

    _unreadCounts = decoded.map<String, int>((key, value) {
      final count = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      return MapEntry('$key', count);
    });
  }

  Future<void> _saveUnreadCounts(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_unreadCountsKeyPrefix$agentId',
      jsonEncode(_unreadCounts),
    );
  }

  void _handleDisconnect(String message) {
    _isConnected = false;
    _isAuthenticated = false;
    _isConnecting = false;
    _lastChallenge = null;
    _channel = null;
    notifyListeners();
  }

  void disconnect() {
    _lastUsedUrl = null;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _handleDisconnect("Disconnected");
    _activePrivateKey = null;
  }

  Future<void> switchWallet(Wallet wallet) async {
    final isSameWallet = _lastUsedWallet?.agentId == wallet.agentId;
    if (isSameWallet && _isConnected && _isAuthenticated) {
      return;
    }

    disconnect();
    await autoConnect(wallet);
  }

  void handleNoWallets() {
    final agentId = _lastUsedWallet?.agentId;
    disconnect();
    _lastUsedWallet = null;
    _friends = [];
    _myTopics = [];
    _messages = {};
    _unreadCounts = {};
    _pendingRequests = [];
    if (agentId != null) {
      unawaited(_saveUnreadCounts(agentId));
    }
    unawaited(_syncAppBadge());
    _activeChatId = null;
    notifyListeners();
  }

  Future<void> addFriend(
    String walletId,
    String pubKeyHex,
    String alias,
  ) async {
    if (_lastUsedWallet == null) return;
    final agentId = _lastUsedWallet!.agentId;
    if (!_friends.any((f) => f.pubKeyHex == pubKeyHex)) {
      _friends.add(Friend(pubKeyHex: pubKeyHex, alias: alias));
      await _saveFriends(agentId);
      _messages[pubKeyHex] = await DbHelper.getMessages(agentId, pubKeyHex);
      notifyListeners();
    }
  }

  Future<void> updateFriendAlias(
    String walletId,
    String pubKeyHex,
    String newAlias,
  ) async {
    if (_lastUsedWallet == null) return;
    final agentId = _lastUsedWallet!.agentId;
    final index = _friends.indexWhere((f) => f.pubKeyHex == pubKeyHex);
    if (index != -1) {
      _friends[index].alias = newAlias;
      await _saveFriends(agentId);
      notifyListeners();
    }
  }

  Future<void> toggleFriendPin(String walletId, String pubKeyHex) async {
    if (_lastUsedWallet == null) return;
    final agentId = _lastUsedWallet!.agentId;
    final index = _friends.indexWhere((f) => f.pubKeyHex == pubKeyHex);
    if (index != -1) {
      _friends[index].isPinned = !_friends[index].isPinned;
      await _saveFriends(agentId);
      notifyListeners();
    }
  }

  Future<void> toggleBlacklist(String walletId, String pubKeyHex) async {
    if (_lastUsedWallet == null) return;
    final agentId = _lastUsedWallet!.agentId;
    final index = _friends.indexWhere((f) => f.pubKeyHex == pubKeyHex);
    if (index != -1) {
      _friends[index].isBlacklisted = !_friends[index].isBlacklisted;
      await _saveFriends(agentId);
      notifyListeners();
    }
  }

  Future<void> allowAgent(String agentId, String friendAgentId) async {
    if (_activePrivateKey == null && _lastUsedWallet != null) {
      final seed = Uint8List.fromList(HEX.decode(_lastUsedWallet!.seedHex));
      _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }
    if (_activePrivateKey == null || _channel == null) return;
    final systemChat = {"id": "system:$agentId", "type": "system"};
    final event = CryptoUtil.buildEvent(
      agentId: agentId,
      chat: systemChat,
      kind: "acl_allow",
      content: friendAgentId,
    );
    final payload = CryptoUtil.canonicalEventPayload(event);
    final sig = CryptoUtil.signB64(_activePrivateKey!, payload);
    final packet = {"type": "event", "event": event, "sig": sig};
    _channel!.sink.add(jsonEncode(packet));
  }

  void rejectRequest(String senderPubKey) {
    _pendingRequests.removeWhere((r) => r.senderPubKey == senderPubKey);
    notifyListeners();
  }

  Future<void> acceptRequest(
    String walletId,
    String agentId,
    String senderPubKey,
  ) async {
    await allowAgent(agentId, senderPubKey);
    final alias = "Friend ${senderPubKey.substring(0, 6)}";
    await addFriend(walletId, senderPubKey, alias);
    _pendingRequests.removeWhere((r) => r.senderPubKey == senderPubKey);
    notifyListeners();
  }

  Future<void> deleteFriend(String walletId, String pubKeyHex) async {
    if (_lastUsedWallet == null) return;
    final agentId = _lastUsedWallet!.agentId;
    _friends.removeWhere((f) => f.pubKeyHex == pubKeyHex);
    await _saveFriends(agentId);
    notifyListeners();
  }

  Future<void> updateTopicAlias(
    String walletId,
    String topicId,
    String newAlias,
  ) async {
    if (_lastUsedWallet == null) return;
    final agentId = _lastUsedWallet!.agentId;
    final index = _myTopics.indexWhere((t) => t.id == topicId);
    if (index != -1) {
      _myTopics[index].alias = newAlias;
      await _saveMyTopics(agentId);
      notifyListeners();
    }
  }

  Future<void> unsubscribeTopic(
    String walletId,
    String agentId,
    String topicName,
  ) async {
    final topicId = topicName.startsWith("topic:")
        ? topicName
        : "topic:$topicName";
    final shortTitle = topicName.startsWith("topic:")
        ? topicName.substring(6)
        : topicName;

    if (_activePrivateKey == null && _lastUsedWallet != null) {
      final seed = Uint8List.fromList(HEX.decode(_lastUsedWallet!.seedHex));
      _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }

    if (_activePrivateKey != null && _channel != null) {
      final topicChat = {"id": topicId, "type": "topic", "title": shortTitle};
      final event = CryptoUtil.buildEvent(
        agentId: agentId,
        chat: topicChat,
        kind: "chat_subscribe",
        content: "",
      );
      final payload = CryptoUtil.canonicalEventPayload(event);
      final sig = CryptoUtil.signB64(_activePrivateKey!, payload);
      final packet = {"type": "event", "event": event, "sig": sig};
      _channel!.sink.add(jsonEncode(packet));
    }

    _myTopics.removeWhere((t) => t.id == topicId);
    await _saveMyTopics(agentId);
    notifyListeners();
  }

  Future<void> subscribeTopic(
    String walletId,
    String agentId,
    String topicName, {
    String? alias,
  }) async {
    final topicId = topicName.startsWith("topic:")
        ? topicName
        : "topic:$topicName";
    final shortTitle = topicName.startsWith("topic:")
        ? topicName.substring(6)
        : topicName;

    if (_activePrivateKey == null && _lastUsedWallet != null) {
      final seed = Uint8List.fromList(HEX.decode(_lastUsedWallet!.seedHex));
      _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }

    if (_activePrivateKey != null && _channel != null) {
      final topicChat = {"id": topicId, "type": "topic", "title": shortTitle};
      final event = CryptoUtil.buildEvent(
        agentId: agentId,
        chat: topicChat,
        kind: "chat_subscribe",
        content: "",
      );
      final payload = CryptoUtil.canonicalEventPayload(event);
      final sig = CryptoUtil.signB64(_activePrivateKey!, payload);
      final packet = {"type": "event", "event": event, "sig": sig};
      _channel!.sink.add(jsonEncode(packet));
    }

    if (!_myTopics.any((t) => t.id == topicId)) {
      _myTopics.add(
        TopicInfo(
          id: topicId,
          title: shortTitle,
          alias: alias,
          isSubscribed: true,
        ),
      );
      await _saveMyTopics(agentId);
      _messages[topicId] = await DbHelper.getMessages(agentId, topicId);
      notifyListeners();
    }
  }

  Future<void> sendFriendRequest(
    String agentId,
    String peerId,
    String content,
  ) async {
    if (_activePrivateKey == null && _lastUsedWallet != null) {
      final seed = Uint8List.fromList(HEX.decode(_lastUsedWallet!.seedHex));
      _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }
    if (!_isAuthenticated || _channel == null || _activePrivateKey == null)
      return;
    final chat = CryptoUtil.buildChat(
      agentId: agentId,
      peerId: peerId,
      chatType: "dm",
    );
    final event = CryptoUtil.buildEvent(
      agentId: agentId,
      chat: chat,
      kind: "friend_request",
      content: content,
    );
    final payload = CryptoUtil.canonicalEventPayload(event);
    final sig = CryptoUtil.signB64(_activePrivateKey!, payload);
    final packet = {"type": "event", "event": event, "sig": sig};
    _channel!.sink.add(jsonEncode(packet));
    _lastDirectPeerId = peerId;
    final msg = ChatMessage(
      content: content,
      signature: sig,
      senderPubKeyHex: agentId,
      timestamp: event['created_at'] * 1000,
      isMine: true,
    );
    await DbHelper.insertMessage(agentId, peerId, msg);
    if (!_messages.containsKey(peerId)) _messages[peerId] = [];
    _messages[peerId]!.add(msg);
    notifyListeners();
  }

  Future<void> sendMessage(
    String content,
    ed.PrivateKey privateKey,
    String agentId,
    String peerId, {
    String chatType = "dm",
    String contentType = "text/plain",
    Map<String, dynamic>? metadata,
    List<Map<String, dynamic>>? attachments,
  }) async {
    if (!_isAuthenticated || _channel == null) return;
    _activePrivateKey = privateKey;
    Map<String, dynamic> chat;
    if (chatType == "topic") {
      final topicName = peerId.startsWith("topic:")
          ? peerId.substring(6)
          : peerId;
      chat = {"id": "topic:$topicName", "type": "topic", "title": topicName};
    } else {
      _lastDirectPeerId = peerId;
      chat = CryptoUtil.buildChat(
        agentId: agentId,
        peerId: peerId,
        chatType: "dm",
      );
    }
    final event = CryptoUtil.buildEvent(
      agentId: agentId,
      chat: chat,
      kind: "message",
      content: content,
      contentType: contentType,
      metadata: metadata,
      attachments: attachments,
    );
    final payload = CryptoUtil.canonicalEventPayload(event);
    final sig = CryptoUtil.signB64(privateKey, payload);
    final packet = {"type": "event", "event": event, "sig": sig};
    _channel!.sink.add(jsonEncode(packet));
    final msg = ChatMessage(
      content: content,
      signature: sig,
      senderPubKeyHex: agentId,
      timestamp: event['created_at'] * 1000,
      isMine: true,
      contentType: contentType,
      metadata: metadata,
      attachments: attachments,
    );
    await DbHelper.insertMessage(agentId, peerId, msg);
    if (!_messages.containsKey(peerId)) _messages[peerId] = [];
    _messages[peerId]!.add(msg);
    notifyListeners();
  }

  Future<void> sendVoiceMessage(
    String filePath,
    Duration duration,
    ed.PrivateKey privateKey,
    String agentId,
    String peerId, {
    String chatType = "dm",
  }) async {
    final fileBytes = await File(filePath).readAsBytes();
    final encodedAudio = base64Encode(fileBytes);
    final fileName = p.basename(filePath);
    final mimeType = _inferAudioMimeType(filePath);
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final label = '[Voice message $minutes:$seconds]';

    await sendMessage(
      label,
      privateKey,
      agentId,
      peerId,
      chatType: chatType,
      contentType: mimeType,
      metadata: {
        'message_type': 'voice',
        'duration_ms': duration.inMilliseconds,
        'local_path': filePath,
        'uri': filePath,
        'name': fileName,
        'mime_type': mimeType,
        'size_bytes': fileBytes.length,
      },
      attachments: [
        {
          'type': 'audio',
          'uri': filePath,
          'name': fileName,
          'mime_type': mimeType,
          'local_path': filePath,
          'duration_ms': duration.inMilliseconds,
          'size_bytes': fileBytes.length,
          'encoding': 'base64',
          'data_b64': encodedAudio,
        },
      ],
    );
  }

  Future<void> sendImageMessage(
    String filePath,
    ed.PrivateKey privateKey,
    String agentId,
    String peerId, {
    String chatType = "dm",
  }) async {
    final fileBytes = await File(filePath).readAsBytes();
    final encodedImage = base64Encode(fileBytes);
    final fileName = p.basename(filePath);
    final mimeType = _inferImageMimeType(filePath);

    await sendMessage(
      '[Image]',
      privateKey,
      agentId,
      peerId,
      chatType: chatType,
      contentType: mimeType,
      metadata: {
        'message_type': 'image',
        'local_path': filePath,
        'uri': filePath,
        'name': fileName,
        'mime_type': mimeType,
        'size_bytes': fileBytes.length,
      },
      attachments: [
        {
          'type': 'image',
          'uri': filePath,
          'name': fileName,
          'mime_type': mimeType,
          'local_path': filePath,
          'size_bytes': fileBytes.length,
          'encoding': 'base64',
          'data_b64': encodedImage,
        },
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _prepareIncomingAttachments(
    List rawAttachments,
    String eventId,
  ) async {
    final normalized = <Map<String, dynamic>>[];
    for (var i = 0; i < rawAttachments.length; i++) {
      final rawItem = rawAttachments[i];
      if (rawItem is! Map) continue;
      final attachment = Map<String, dynamic>.from(rawItem);
      _normalizeAttachmentType(attachment);
      final localPath = await _materializeAttachment(
        attachment,
        eventId: eventId,
        index: i,
      );
      if (localPath != null && localPath.isNotEmpty) {
        attachment['local_path'] = localPath;
        attachment['uri'] = attachment['uri'] ?? localPath;
      }
      normalized.add(attachment);
    }
    return normalized;
  }

  Map<String, dynamic> _prepareIncomingMetadata(
    Map<String, dynamic> metadata,
    List<Map<String, dynamic>> attachments,
  ) {
    if (attachments.isEmpty) return metadata;
    final normalized = Map<String, dynamic>.from(metadata);
    final primaryAttachment =
        attachments.cast<Map<String, dynamic>?>().firstWhere(
          (attachment) =>
              attachment != null && _looksLikeAudioAttachment(attachment),
          orElse: () => null,
        ) ??
        attachments.cast<Map<String, dynamic>?>().firstWhere(
          (attachment) =>
              attachment != null && _looksLikeImageAttachment(attachment),
          orElse: () => null,
        );
    if (primaryAttachment == null) return normalized;
    if (_looksLikeAudioAttachment(primaryAttachment)) {
      normalized['message_type'] = normalized['message_type'] ?? 'voice';
      normalized['duration_ms'] =
          normalized['duration_ms'] ?? primaryAttachment['duration_ms'];
    } else if (_looksLikeImageAttachment(primaryAttachment)) {
      normalized['message_type'] = normalized['message_type'] ?? 'image';
    }
    normalized['duration_ms'] =
        normalized['duration_ms'] ?? primaryAttachment['duration_ms'];
    normalized['mime_type'] =
        normalized['mime_type'] ?? primaryAttachment['mime_type'];
    if (primaryAttachment['local_path'] is String &&
        (primaryAttachment['local_path'] as String).isNotEmpty) {
      normalized['local_path'] = primaryAttachment['local_path'];
    }
    if (primaryAttachment['uri'] is String &&
        (primaryAttachment['uri'] as String).isNotEmpty) {
      normalized['uri'] = primaryAttachment['uri'];
    }
    normalized['name'] = normalized['name'] ?? primaryAttachment['name'];
    return normalized;
  }

  Future<String?> _materializeAttachment(
    Map<String, dynamic> attachment, {
    required String eventId,
    required int index,
  }) async {
    final existingLocalPath = attachment['local_path'];
    if (existingLocalPath is String && existingLocalPath.isNotEmpty) {
      final file = File(existingLocalPath);
      if (file.existsSync()) return existingLocalPath;
    }

    final encodedData = _extractAttachmentPayloadBase64(attachment);
    if (encodedData == null || encodedData.isEmpty) return null;

    try {
      final bytes = base64Decode(encodedData);
      final directory = await getTemporaryDirectory();
      final fileName = _attachmentFileName(
        attachment,
        eventId: eventId,
        index: index,
      );
      final filePath = p.join(directory.path, fileName);
      final file = File(filePath);
      if (!file.existsSync()) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file.path;
    } catch (e) {
      debugPrint('附件落盘失败: $e');
      return null;
    }
  }

  String? _extractAttachmentPayloadBase64(Map<String, dynamic> attachment) {
    final directKeys = [
      'data_b64',
      'dataBase64',
      'base64',
      'bytes_b64',
      'payload_b64',
      'content_b64',
    ];
    for (final key in directKeys) {
      final value = attachment[key];
      if (value is String && value.isNotEmpty) return value;
    }

    final uri = attachment['uri'];
    if (uri is String && uri.startsWith('data:')) {
      final commaIndex = uri.indexOf(',');
      if (commaIndex > 0 && uri.substring(0, commaIndex).contains(';base64')) {
        return uri.substring(commaIndex + 1);
      }
    }

    return null;
  }

  String _attachmentFileName(
    Map<String, dynamic> attachment, {
    required String eventId,
    required int index,
  }) {
    final attachmentName = attachment['name'];
    if (attachmentName is String && attachmentName.isNotEmpty) {
      return '${eventId}_$index${p.extension(attachmentName)}';
    }
    final mimeType = attachment['mime_type'] as String? ?? '';
    return '${eventId}_$index${_extensionForMimeType(mimeType)}';
  }

  String _extensionForMimeType(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/gif':
        return '.gif';
      case 'image/webp':
        return '.webp';
      case 'audio/ogg':
        return '.ogg';
      case 'audio/mpeg':
        return '.mp3';
      case 'audio/wav':
        return '.wav';
      case 'audio/mp4':
        return '.m4a';
      case 'audio/aac':
        return '.aac';
      default:
        return '.bin';
    }
  }

  void _normalizeAttachmentType(Map<String, dynamic> attachment) {
    if (_looksLikeAudioAttachment(attachment)) {
      attachment['type'] = 'audio';
    } else if (_looksLikeImageAttachment(attachment)) {
      attachment['type'] = 'image';
    }
  }

  bool _looksLikeAudioAttachment(Map<String, dynamic> attachment) {
    final type = attachment['type'];
    if (type is String && type.toLowerCase() == 'audio') return true;

    final mimeType = attachment['mime_type'];
    if (mimeType is String && mimeType.toLowerCase().startsWith('audio/')) {
      return true;
    }

    final name = attachment['name'];
    if (name is String) {
      final lower = name.toLowerCase();
      if (lower.endsWith('.ogg') ||
          lower.endsWith('.mp3') ||
          lower.endsWith('.wav') ||
          lower.endsWith('.m4a') ||
          lower.endsWith('.aac')) {
        return true;
      }
    }

    final uri = attachment['uri'];
    if (uri is String && uri.startsWith('data:audio/')) return true;

    return false;
  }

  bool _looksLikeImageAttachment(Map<String, dynamic> attachment) {
    final type = attachment['type'];
    if (type is String && type.toLowerCase() == 'image') return true;

    final mimeType = attachment['mime_type'];
    if (mimeType is String && mimeType.toLowerCase().startsWith('image/')) {
      return true;
    }

    final name = attachment['name'];
    if (name is String) {
      final lower = name.toLowerCase();
      if (lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.webp')) {
        return true;
      }
    }

    final uri = attachment['uri'];
    if (uri is String && uri.startsWith('data:image/')) return true;

    return false;
  }

  String _inferAudioMimeType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.ogg':
        return 'audio/ogg';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.m4a':
        return 'audio/mp4';
      case '.aac':
        return 'audio/aac';
      default:
        return 'audio/aac';
    }
  }

  String _inferImageMimeType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}
