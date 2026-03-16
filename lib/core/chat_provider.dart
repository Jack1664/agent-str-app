import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:hex/hex.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/friend.dart';
import '../models/wallet.dart';
import 'crypto_util.dart';
import 'db_helper.dart';

/// 表示收到的好友申请
class FriendRequest {
  final String senderPubKey; // 发送者公钥
  final String content;      // 申请内容
  final int timestamp;       // 时间戳

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
    this.isSubscribed = false
  }) : this.alias = alias ?? title;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'alias': alias,
    'isSubscribed': isSubscribed
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
  List<TopicInfo> _myTopics = [];      // 我订阅的话题列表
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
  Wallet? _lastUsedWallet;

  // --- Getters ---
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  bool get isConnecting => _isConnecting;
  bool get isAuthPending => _lastChallenge != null && !_isAuthenticated;
  Map<String, dynamic>? get lastChallenge => _lastChallenge;

  String? get lastUsedUrl => _lastUsedUrl;
  Wallet? get lastUsedWallet => _lastUsedWallet;

  ed.PrivateKey? get activePrivateKey => _activePrivateKey;

  List<String> get discoveredTopics => _discoveredTopics;
  List<TopicInfo> get myTopics => _myTopics;
  List<Friend> get friends => _friends;
  Map<String, List<ChatMessage>> get messages => _messages;
  List<FriendRequest> get pendingRequests => _pendingRequests;

  static const String _relayUrlKeyPrefix = 'relay_url_';
  static const String _friendsKeyPrefix = 'friends_';
  static const String _topicsKeyPrefix = 'my_topics_';

  /// 连接到指定的 Relay 服务器
  Future<void> connect(String url, Wallet activeWallet) async {
    if (_isConnecting) return;

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

      Fluttertoast.showToast(
        msg: "Connected to Relay",
        backgroundColor: Colors.green,
        gravity: ToastGravity.TOP,
      );

      _channel!.stream.listen((rawData) {
        debugPrint("收到原始数据: $rawData");
        _handleRawMessage(rawData, activeWallet);
      }, onDone: () {
        _handleDisconnect("Relay connection closed");
        _scheduleReconnect();
      }, onError: (e) {
        debugPrint("WS 流错误: $e");
        _handleDisconnect("Network Error: $e");
        _scheduleReconnect();
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_relayUrlKeyPrefix}${activeWallet.id}', url);
      await loadFriends(activeWallet.id);
      await _loadMyTopics(activeWallet.id);

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
        // 收到服务器挑战请求，自动使用内存中的私钥或钱包中的私钥进行认证
        _lastChallenge = data;
        _autoAuthenticate(activeWallet);
        notifyListeners();
      } else if (type == 'connected') {
        // 认证成功
        _isAuthenticated = true;
        _lastChallenge = null;
        _authCompleter?.complete(true);
        _authCompleter = null;
        notifyListeners();
      } else if (type == 'pong') {
        // 心跳响应
      } else if (type == 'deliver') {
        // 收到投递的消息
        _handleDeliver(data, activeWallet);
      } else if (type == 'error') {
        // 服务器返回错误
        _authCompleter?.complete(false);
        _authCompleter = null;
        Fluttertoast.showToast(
          msg: "Relay error: ${data['message'] ?? data}",
          gravity: ToastGravity.TOP,
          backgroundColor: Colors.redAccent,
        );
      }
    } catch (e) {
      debugPrint('消息解析错误: $e');
    }
  }

  /// 自动进行身份认证 (去掉了密码依赖)
  Future<void> _autoAuthenticate(Wallet activeWallet) async {
    if (_lastChallenge == null) return;

    // 如果内存中没有，从 activeWallet 的 seedHex 中派生
    if (_activePrivateKey == null) {
      final seed = Uint8List.fromList(HEX.decode(activeWallet.seedHex));
      _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }

    final challengeStr = "AUTH|${_lastChallenge!['nonce']}|${_lastChallenge!['ts']}";
    final sig = CryptoUtil.signB64(_activePrivateKey!, challengeStr);
    final authPacket = {"type": "auth", "agent_id": activeWallet.agentId, "sig": sig};
    _channel!.sink.add(jsonEncode(authPacket));
  }

  /// 处理收到的 deliver 类型消息（普通聊天或好友申请）
  Future<void> _handleDeliver(Map<String, dynamic> data, Wallet activeWallet) async {
    final event = data['event'];
    final sender = event['from'];
    final sig = data['sig'];

    // 验证事件签名
    final payload = CryptoUtil.canonicalEventPayload(event);
    final isValid = CryptoUtil.verifySignature(payload, sig, sender);

    if (!isValid) {
      debugPrint("收到签名非法的事件，已丢弃");
      return;
    }

    // 发送接收确认 (ACK)
    _sendAck(activeWallet.agentId, event);

    // 如果是好友申请类型
    if (event['kind'] == 'friend_request') {
      if (!_friends.any((f) => f.pubKeyHex == sender)) {
        if (!_pendingRequests.any((r) => r.senderPubKey == sender)) {
          _pendingRequests.add(FriendRequest(
            senderPubKey: sender,
            content: event['content'],
            timestamp: event['created_at'] * 1000,
          ));
          notifyListeners();
        }
      }
    }

    // 如果是普通聊天或好友申请（也展示在聊天记录中）
    if (event['kind'] == 'message' || event['kind'] == 'friend_request') {
      final msg = ChatMessage(
        content: event['content'],
        signature: sig ?? '',
        senderPubKeyHex: sender,
        timestamp: event['created_at'] * 1000,
        isMine: sender == activeWallet.agentId,
      );

      final chatId = event['chat']['id'];
      final chatType = event['chat']['type'];

      String peerId = sender;
      if (chatType == 'topic') {
        peerId = chatId; // 对于话题，直接使用话题 ID 作为消息 key
      } else if (sender == activeWallet.agentId) {
        // 如果是我自己发的（多端同步），解析对方是谁
        final parts = chatId.split(':');
        if (parts.length == 3 && parts[0] == 'dm') {
          peerId = (parts[1] == sender) ? parts[2] : parts[1];
        }
      }

      // 保存到本地数据库
      await DbHelper.insertMessage(peerId, msg);

      if (!_messages.containsKey(peerId)) _messages[peerId] = [];
      _messages[peerId]!.add(msg);
      notifyListeners();
    }
  }

  /// 发送消息确认 (ACK) 回执
  void _sendAck(String agentId, Map<String, dynamic> sourceEvent) {
    // 确保有私钥可用
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

  /// 自动连接：加载本地数据并尝试连接上次使用的服务器
  Future<void> autoConnect(Wallet activeWallet) async {
    _lastUsedWallet = activeWallet;
    await loadFriends(activeWallet.id);
    await _loadMyTopics(activeWallet.id);
    if (_isConnected) return;

    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('${_relayUrlKeyPrefix}${activeWallet.id}');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      await connect(savedUrl, activeWallet);
    }
  }

  /// 从 SharedPreferences 加载数据
  Future<void> loadFriends(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? friendsJson = prefs.getString('${_friendsKeyPrefix}$walletId');
    if (friendsJson != null) {
      final List<dynamic> decoded = jsonDecode(friendsJson);
      _friends = decoded.map((e) => Friend.fromJson(e)).toList();

      // 加载每个好友的历史消息
      for (var friend in _friends) {
        _messages[friend.pubKeyHex] = await DbHelper.getMessages(friend.pubKeyHex);
      }
    }
    notifyListeners();
  }

  Future<void> _loadMyTopics(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? topicsJson = prefs.getString('${_topicsKeyPrefix}$walletId');
    if (topicsJson != null) {
      final List<dynamic> decoded = jsonDecode(topicsJson);
      _myTopics = decoded.map((e) => TopicInfo.fromJson(e)).toList();

      // 加载每个话题的历史消息
      for (var topic in _myTopics) {
        _messages[topic.id] = await DbHelper.getMessages(topic.id);
      }
    }
    notifyListeners();
  }

  /// 持久化数据
  Future<void> _saveFriends(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_friends.map((e) => e.toJson()).toList());
    await prefs.setString('${_friendsKeyPrefix}$walletId', encoded);
  }

  Future<void> _saveMyTopics(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_myTopics.map((e) => e.toJson()).toList());
    await prefs.setString('${_topicsKeyPrefix}$walletId', encoded);
  }

  /// 统一处理连接断开逻辑
  void _handleDisconnect(String message) {
    _isConnected = false;
    _isAuthenticated = false;
    _isConnecting = false;
    notifyListeners();
    debugPrint("连接断开: $message");

    // 断开连接时也给个顶部提示
    if (_lastUsedUrl != null) {
      Fluttertoast.showToast(
        msg: message,
        gravity: ToastGravity.TOP,
        backgroundColor: Colors.orangeAccent,
      );
    }
  }

  /// 手动断开 WebSocket 连接
  void disconnect() {
    _lastUsedUrl = null;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _handleDisconnect("Disconnected");
    _activePrivateKey = null;
  }

  // --- 好友管理 ---

  Future<void> addFriend(String walletId, String pubKeyHex, String alias) async {
    if (!_friends.any((f) => f.pubKeyHex == pubKeyHex)) {
      _friends.add(Friend(pubKeyHex: pubKeyHex, alias: alias));
      await _saveFriends(walletId);

      // 同时也尝试加载历史消息
      _messages[pubKeyHex] = await DbHelper.getMessages(pubKeyHex);

      notifyListeners();
    }
  }

  Future<void> updateFriendAlias(String walletId, String pubKeyHex, String newAlias) async {
    final index = _friends.indexWhere((f) => f.pubKeyHex == pubKeyHex);
    if (index != -1) {
      _friends[index].alias = newAlias;
      await _saveFriends(walletId);
      notifyListeners();
    }
  }

  Future<void> toggleFriendPin(String walletId, String pubKeyHex) async {
    final index = _friends.indexWhere((f) => f.pubKeyHex == pubKeyHex);
    if (index != -1) {
      _friends[index].isPinned = !_friends[index].isPinned;
      await _saveFriends(walletId);
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

  Future<void> acceptRequest(String walletId, String agentId, String senderPubKey) async {
    await allowAgent(agentId, senderPubKey);
    final alias = "好友 ${senderPubKey.substring(0, 6)}";
    await addFriend(walletId, senderPubKey, alias);
    _pendingRequests.removeWhere((r) => r.senderPubKey == senderPubKey);
    notifyListeners();
  }

  Future<void> deleteFriend(String walletId, String pubKeyHex) async {
    _friends.removeWhere((f) => f.pubKeyHex == pubKeyHex);
    await _saveFriends(walletId);
    notifyListeners();
  }

  Future<void> toggleBlacklist(String walletId, String pubKeyHex) async {
    final index = _friends.indexWhere((f) => f.pubKeyHex == pubKeyHex);
    if (index != -1) {
      _friends[index].isBlacklisted = !_friends[index].isBlacklisted;
      await _saveFriends(walletId);
      notifyListeners();
    }
  }

  // --- 话题 (Topics) 管理 ---

  Future<void> subscribeTopic(String walletId, String agentId, String topicName, {String? alias}) async {
    if (_activePrivateKey == null && _lastUsedWallet != null) {
       final seed = Uint8List.fromList(HEX.decode(_lastUsedWallet!.seedHex));
       _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }
    if (_activePrivateKey == null || _channel == null) return;

    final topicId = topicName.startsWith("topic:") ? topicName : "topic:$topicName";
    final shortTitle = topicName.startsWith("topic:") ? topicName.substring(6) : topicName;

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

    if (!_myTopics.any((t) => t.id == topicId)) {
      _myTopics.add(TopicInfo(
        id: topicId,
        title: shortTitle,
        alias: alias,
        isSubscribed: true
      ));
      await _saveMyTopics(walletId);

      // 尝试加载历史消息
      _messages[topicId] = await DbHelper.getMessages(topicId);

      notifyListeners();
    }
  }

  Future<void> updateTopicAlias(String walletId, String topicId, String newAlias) async {
    final index = _myTopics.indexWhere((t) => t.id == topicId);
    if (index != -1) {
      _myTopics[index].alias = newAlias;
      await _saveMyTopics(walletId);
      notifyListeners();
    }
  }

  Future<void> unsubscribeTopic(String walletId, String agentId, String topicName) async {
    if (_activePrivateKey == null && _lastUsedWallet != null) {
       final seed = Uint8List.fromList(HEX.decode(_lastUsedWallet!.seedHex));
       _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }
    if (_activePrivateKey == null || _channel == null) return;

    final topicId = topicName.startsWith("topic:") ? topicName : "topic:$topicName";
    final shortTitle = topicName.startsWith("topic:") ? topicName.substring(6) : topicName;

    final topicChat = {"id": topicId, "type": "topic", "title": shortTitle};
    final event = CryptoUtil.buildEvent(
      agentId: agentId,
      chat: topicChat,
      kind: "chat_unsubscribe",
      content: "",
    );
    final payload = CryptoUtil.canonicalEventPayload(event);
    final sig = CryptoUtil.signB64(_activePrivateKey!, payload);
    final packet = {"type": "event", "event": event, "sig": sig};
    _channel!.sink.add(jsonEncode(packet));

    _myTopics.removeWhere((t) => t.id == topicId);
    await _saveMyTopics(walletId);
    notifyListeners();
  }

  // --- 消息发送 ---

  Future<void> sendFriendRequest(String agentId, String peerId, String content) async {
    if (_activePrivateKey == null && _lastUsedWallet != null) {
       final seed = Uint8List.fromList(HEX.decode(_lastUsedWallet!.seedHex));
       _activePrivateKey = CryptoUtil.deriveKeyPair(seed).privateKey;
    }
    if (!_isAuthenticated || _channel == null || _activePrivateKey == null) return;

    final chat = CryptoUtil.buildChat(agentId: agentId, peerId: peerId, chatType: "dm");
    final event = CryptoUtil.buildEvent(agentId: agentId, chat: chat, kind: "friend_request", content: content);
    final payload = CryptoUtil.canonicalEventPayload(event);
    final sig = CryptoUtil.signB64(_activePrivateKey!, payload);
    final packet = {"type": "event", "event": event, "sig": sig};
    _channel!.sink.add(jsonEncode(packet));

    final msg = ChatMessage(content: content, signature: sig, senderPubKeyHex: agentId, timestamp: event['created_at'] * 1000, isMine: true);

    // 保存到本地数据库
    await DbHelper.insertMessage(peerId, msg);

    if (!_messages.containsKey(peerId)) _messages[peerId] = [];
    _messages[peerId]!.add(msg);
    notifyListeners();
  }

  Future<void> sendMessage(String content, ed.PrivateKey privateKey, String agentId, String peerId, {String chatType = "dm"}) async {
    if (!_isAuthenticated || _channel == null) return;
    _activePrivateKey = privateKey;

    Map<String, dynamic> chat;
    if (chatType == "topic") {
      final topicName = peerId.startsWith("topic:") ? peerId.substring(6) : peerId;
      chat = {"id": "topic:$topicName", "type": "topic", "title": topicName};
    } else {
      chat = CryptoUtil.buildChat(agentId: agentId, peerId: peerId, chatType: "dm");
    }

    final event = CryptoUtil.buildEvent(agentId: agentId, chat: chat, kind: "message", content: content);
    final payload = CryptoUtil.canonicalEventPayload(event);
    final sig = CryptoUtil.signB64(privateKey, payload);
    final packet = {"type": "event", "event": event, "sig": sig};
    _channel!.sink.add(jsonEncode(packet));

    final msg = ChatMessage(content: content, signature: sig, senderPubKeyHex: agentId, timestamp: event['created_at'] * 1000, isMine: true);

    // 保存到本地数据库
    await DbHelper.insertMessage(peerId, msg);

    if (!_messages.containsKey(peerId)) _messages[peerId] = [];
    _messages[peerId]!.add(msg);
    notifyListeners();
  }
}
