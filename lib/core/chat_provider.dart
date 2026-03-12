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

class ChatProvider with ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isAuthenticated = false;
  bool _isConnecting = false;

  List<String> _topics = [];
  List<Friend> _friends = [];
  Map<String, List<ChatMessage>> _messages = {};

  // For authentication flow
  Map<String, dynamic>? _lastChallenge;
  Completer<bool>? _authCompleter;
  ed.PrivateKey? _activePrivateKey;
  String? _tempPassword;

  // Connection management
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  String? _lastUsedUrl;
  Wallet? _lastUsedWallet;

  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  bool get isConnecting => _isConnecting;
  bool get isAuthPending => _lastChallenge != null && !_isAuthenticated;
  Map<String, dynamic>? get lastChallenge => _lastChallenge;

  String? get lastUsedUrl => _lastUsedUrl;
  Wallet? get lastUsedWallet => _lastUsedWallet;

  ed.PrivateKey? get activePrivateKey => _activePrivateKey;
  String? get tempPassword => _tempPassword;

  List<String> get topics => _topics;
  List<Friend> get friends => _friends;
  Map<String, List<ChatMessage>> get messages => _messages;

  static const String _relayUrlKeyPrefix = 'relay_url_';
  static const String _friendsKeyPrefix = 'friends_';

  Future<void> connect(String url, Wallet activeWallet) async {
    if (_isConnecting) return;

    // Normalize URL
    String targetUrl = url.trim();
    while (targetUrl.endsWith('/')) {
      targetUrl = targetUrl.substring(0, targetUrl.length - 1);
    }
    if (!targetUrl.endsWith('/ws/agent')) {
      targetUrl = "$targetUrl/ws/agent";
    }

    _lastUsedUrl = targetUrl;
    _lastUsedWallet = activeWallet;
    _isConnecting = true;
    _isConnected = false;
    _isAuthenticated = false;
    notifyListeners();

    try {
      debugPrint("Attempting connection to: $targetUrl");

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

      Fluttertoast.showToast(msg: "Connected to Relay", backgroundColor: Colors.green);

      _channel!.stream.listen((rawData) {
        debugPrint("WS Received: $rawData");
        _handleRawMessage(rawData, activeWallet);
      }, onDone: () {
        _handleDisconnect("Relay connection closed");
        _scheduleReconnect();
      }, onError: (e) {
        debugPrint("WS Stream Error: $e");
        _handleDisconnect("Network Error: $e");
        _scheduleReconnect();
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_relayUrlKeyPrefix}${activeWallet.id}', url);
      await loadFriends(activeWallet.id);

    } catch (e) {
      debugPrint("Connect Failure: $e");
      _isConnecting = false;
      _handleDisconnect("Connect Failed: $e");
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_lastUsedUrl == null || _lastUsedWallet == null) return;

    _reconnectAttempts++;
    int delay = (1 << _reconnectAttempts).clamp(2, 30);

    debugPrint("Reconnecting in $delay seconds...");
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_isConnected && !_isConnecting) {
        connect(_lastUsedUrl!, _lastUsedWallet!);
      }
    });
  }

  void _handleRawMessage(dynamic rawData, Wallet activeWallet) {
    try {
      final data = jsonDecode(rawData);
      final type = data['type'];

      if (type == 'challenge') {
        _lastChallenge = data;
        notifyListeners();
        if (_activePrivateKey != null) {
          _autoAuthenticate(activeWallet);
        }
      } else if (type == 'connected') {
        _isAuthenticated = true;
        _lastChallenge = null;
        _authCompleter?.complete(true);
        _authCompleter = null;
        notifyListeners();
      } else if (type == 'pong') {
        // Heartbeat OK
      } else if (type == 'deliver') {
        _handleDeliver(data, activeWallet);
      } else if (type == 'error') {
        _authCompleter?.complete(false);
        _authCompleter = null;
        Fluttertoast.showToast(msg: "Relay: ${data['message'] ?? data}");
      }
    } catch (e) {
      debugPrint('Msg Parse Error: $e');
    }
  }

  Future<void> _autoAuthenticate(Wallet activeWallet) async {
    if (_activePrivateKey == null || _lastChallenge == null) return;
    final challengeStr = "AUTH|${_lastChallenge!['nonce']}|${_lastChallenge!['ts']}";
    final sig = CryptoUtil.signB64(_activePrivateKey!, challengeStr);
    final authPacket = {"type": "auth", "agent_id": activeWallet.agentId, "sig": sig};
    _channel!.sink.add(jsonEncode(authPacket));
  }

  Future<bool> authenticateWithSeed(Uint8List seed, String password) async {
    if (_channel == null || _lastChallenge == null) return false;

    final keyPair = CryptoUtil.deriveKeyPair(seed);
    _activePrivateKey = keyPair.privateKey;
    _tempPassword = password;

    final challengeStr = "AUTH|${_lastChallenge!['nonce']}|${_lastChallenge!['ts']}";
    final sig = CryptoUtil.signB64(keyPair.privateKey, challengeStr);

    final authPacket = {
      "type": "auth",
      "agent_id": CryptoUtil.getAgentId(keyPair),
      "sig": sig,
    };

    _authCompleter = Completer<bool>();
    _channel!.sink.add(jsonEncode(authPacket));
    return _authCompleter!.future;
  }

  void _handleDeliver(Map<String, dynamic> data, Wallet activeWallet) {
    final event = data['event'];
    final sender = event['from'];
    final sig = data['sig'];

    final payload = CryptoUtil.canonicalEventPayload(event);
    final isValid = CryptoUtil.verifySignature(payload, sig, sender);

    if (!isValid) return;

    _sendAck(activeWallet.agentId, event);

    if (event['kind'] == 'message') {
      final msg = ChatMessage(
        content: event['content'],
        signature: sig ?? '',
        senderPubKeyHex: sender,
        timestamp: event['created_at'] * 1000,
        isMine: sender == activeWallet.agentId,
      );

      final friend = _friends.firstWhere(
        (f) => f.pubKeyHex == sender,
        orElse: () => Friend(pubKeyHex: sender, alias: 'Unknown'),
      );
      if (friend.isBlacklisted) return;

      final chatId = event['chat']['id'];
      String peerId = sender;
      if (sender == activeWallet.agentId) {
        final parts = chatId.split(':');
        if (parts.length == 3 && parts[0] == 'dm') {
          peerId = (parts[1] == sender) ? parts[2] : parts[1];
        }
      }

      if (!_messages.containsKey(peerId)) _messages[peerId] = [];
      _messages[peerId]!.add(msg);
      notifyListeners();
    }
  }

  void _sendAck(String agentId, Map<String, dynamic> sourceEvent) {
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
    await loadFriends(activeWallet.id);
    if (_isConnected) return;

    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('${_relayUrlKeyPrefix}${activeWallet.id}');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      await connect(savedUrl, activeWallet);
    }
  }

  Future<void> loadFriends(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? friendsJson = prefs.getString('${_friendsKeyPrefix}$walletId');
    if (friendsJson != null) {
      final List<dynamic> decoded = jsonDecode(friendsJson);
      _friends = decoded.map((e) => Friend.fromJson(e)).toList();
    }
    notifyListeners();
  }

  Future<void> _saveFriends(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_friends.map((e) => e.toJson()).toList());
    await prefs.setString('${_friendsKeyPrefix}$walletId', encoded);
  }

  void _handleDisconnect(String message) {
    _isConnected = false;
    _isAuthenticated = false;
    _isConnecting = false;
    notifyListeners();
    debugPrint("Disconnected: $message");
  }

  void disconnect() {
    _lastUsedUrl = null;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _handleDisconnect("Manual");
    _activePrivateKey = null;
    _tempPassword = null;
  }

  Future<void> addFriend(String walletId, String pubKeyHex, String alias) async {
    if (!_friends.any((f) => f.pubKeyHex == pubKeyHex)) {
      _friends.add(Friend(pubKeyHex: pubKeyHex, alias: alias));
      await _saveFriends(walletId);
      notifyListeners();
    }
  }

  Future<void> allowAgent(String agentId, String friendAgentId) async {
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

  void sendMessage(String content, ed.PrivateKey privateKey, String agentId, String peerId) {
    if (!_isAuthenticated || _channel == null) return;
    _activePrivateKey = privateKey;
    final chat = CryptoUtil.buildChat(agentId: agentId, peerId: peerId, chatType: "dm");
    final event = CryptoUtil.buildEvent(agentId: agentId, chat: chat, kind: "message", content: content);
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
    if (!_messages.containsKey(peerId)) _messages[peerId] = [];
    _messages[peerId]!.add(msg);
    notifyListeners();
  }
}
