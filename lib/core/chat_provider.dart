import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:hex/hex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/friend.dart';
import '../models/wallet.dart';
import 'crypto_util.dart';
import 'db_helper.dart';
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
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isAuthenticated = false;
  bool _isConnecting = false;

  List<String> _discoveredTopics = []; // 从服务器发现的话题 ID 列表
  List<TopicInfo> _myTopics = []; // 我订阅的话题列表
  List<Friend> _friends = [];
  Map<String, List<ChatMessage>> _messages = {};
  List<FriendRequest> _pendingRequests = []; // 待处理的好友申请

  // 认证流程相关变量
  Map<String, dynamic>? _lastChallenge;
  Completer<bool>? _authCompleter;
  ed.PrivateKey? _activePrivateKey;

  // 连接 management
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _lastUsedUrl;
  String _agentsUrl = 'http://112.126.60.140:8765/api/agents';
  String _topicsUrl = 'http://112.126.60.140:8765/api/topics';
  Wallet? _lastUsedWallet;

  // --- Getters ---
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  bool get isConnecting => _isConnecting;
  bool get isAuthPending => _lastChallenge != null && !_isAuthenticated;
  Map<String, dynamic>? get lastChallenge => _lastChallenge;

  String? get lastUsedUrl => _lastUsedUrl;
  String get agentsUrl => _agentsUrl;
  String get topicsUrl => _topicsUrl;
  Wallet? get lastUsedWallet => _lastUsedWallet;

  ed.PrivateKey? get activePrivateKey => _activePrivateKey;

  List<String> get discoveredTopics => _discoveredTopics;
  List<TopicInfo> get myTopics => _myTopics;
  List<Friend> get friends => _friends;
  Map<String, List<ChatMessage>> get messages => _messages;
  List<FriendRequest> get pendingRequests => _pendingRequests;

  static const String _relayUrlKeyPrefix = 'relay_url_';
  static const String _agentsUrlKeyPrefix = 'agents_url_';
  static const String _topicsUrlKeyPrefix = 'topics_url_';
  static const String _friendsKeyPrefix = 'friends_v2_';
  static const String _topicsKeyPrefix = 'my_topics_v2_';

  /// 连接到指定的 Relay 服务器
  Future<void> connect(String url, Wallet activeWallet) async {
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
        TopNotice.show(
          'Relay error: ${data['message'] ?? data}',
          backgroundColor: Colors.redAccent,
        );
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

      final msg = ChatMessage(
        content: event['content'],
        signature: sig ?? '',
        senderPubKeyHex: sender,
        timestamp: event['created_at'] * 1000,
        isMine: sender == activeWallet.agentId,
      );

      await DbHelper.insertMessage(activeWallet.agentId, peerId, msg);

      if (!_messages.containsKey(peerId)) _messages[peerId] = [];
      _messages[peerId]!.add(msg);
      notifyListeners();
    }
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

  Future<void> autoConnect(Wallet activeWallet) async {
    _lastUsedWallet = activeWallet;
    // 重置内存状态，准备加载新钱包数据
    _friends = [];
    _myTopics = [];
    _messages = {};
    _pendingRequests = [];

    final prefs = await SharedPreferences.getInstance();
    _agentsUrl =
        prefs.getString('${_agentsUrlKeyPrefix}${activeWallet.agentId}') ??
        'http://112.126.60.140:8765/api/agents';
    _topicsUrl =
        prefs.getString('${_topicsUrlKeyPrefix}${activeWallet.agentId}') ??
        'http://112.126.60.140:8765/api/topics';

    await loadFriends(activeWallet.agentId);
    await _loadMyTopics(activeWallet.agentId);
    notifyListeners();

    final savedUrl = prefs.getString(
      '${_relayUrlKeyPrefix}${activeWallet.agentId}',
    );
    if (savedUrl != null && savedUrl.isNotEmpty) {
      await connect(savedUrl, activeWallet);
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

  void _handleDisconnect(String message) {
    _isConnected = false;
    _isAuthenticated = false;
    _isConnecting = false;
    notifyListeners();
  }

  void disconnect() {
    _lastUsedUrl = null;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _handleDisconnect("Disconnected");
    _activePrivateKey = null;
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
    );
    await DbHelper.insertMessage(agentId, peerId, msg);
    if (!_messages.containsKey(peerId)) _messages[peerId] = [];
    _messages[peerId]!.add(msg);
    notifyListeners();
  }
}
