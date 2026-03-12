import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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
  
  List<String> _topics = []; // List of online public keys dictating topics
  List<Friend> _friends = [];
  Map<String, List<ChatMessage>> _messages = {}; // pubKeyHex -> messages

  bool get isConnected => _isConnected;
  List<String> get topics => _topics;
  List<Friend> get friends => _friends;
  Map<String, List<ChatMessage>> get messages => _messages;

  static const String _relayUrlKeyPrefix = 'relay_url_';

  Future<void> connect(String url, Wallet activeWallet) async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _isConnected = true;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_relayUrlKeyPrefix}${activeWallet.id}', url);

      Fluttertoast.showToast(
        msg: "Connected to Relay",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );

      _channel!.stream.listen((message) {
        _handleIncomingMessage(message, activeWallet);
      }, onDone: () {
        _handleDisconnect("Disconnected from Relay");
      }, onError: (e) {
        _handleDisconnect("Connection Error");
      });
    } catch (e) {
      _handleDisconnect("Connection Failed");
    }
  }

  Future<void> autoConnect(Wallet activeWallet) async {
    if (_isConnected) return;

    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('${_relayUrlKeyPrefix}${activeWallet.id}');

    if (savedUrl != null && savedUrl.isNotEmpty) {
      await connect(savedUrl, activeWallet);
    }
  }

  void _handleDisconnect(String message) {
    _isConnected = false;
    notifyListeners();
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.redAccent,
      textColor: Colors.white,
    );
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    notifyListeners();
  }

  void _handleIncomingMessage(dynamic rawData, Wallet activeWallet) {
    try {
      final data = jsonDecode(rawData);
      final type = data['type'];

      if (type == 'topics') {
        _topics = List<String>.from(data['topics'] ?? []);
        _topics.remove(activeWallet.agentId); // Using agentId instead of publicKeyHex
        notifyListeners();
      } else if (type == 'challenge') {
        final nonce = data['nonce'];
        final ts = data['ts'];
        Fluttertoast.showToast(
          msg: "Server Challenge:\nNonce: $nonce\nTS: $ts",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.CENTER,
          backgroundColor: Colors.indigoAccent,
          textColor: Colors.white,
        );
      } else if (type == 'chat') {
        final content = data['content'];
        final signature = data['signature'];
        final senderPubKeyHex = data['senderPubKeyHex'];
        final timestamp = data['timestamp'];

        final friend = _friends.firstWhere(
          (f) => f.pubKeyHex == senderPubKeyHex,
          orElse: () => Friend(pubKeyHex: senderPubKeyHex, alias: 'Unknown'),
        );

        if (friend.isBlacklisted) return;

        final isValid = CryptoUtil.verifySignature(content, signature, senderPubKeyHex);
        
        if (isValid) {
          final msg = ChatMessage(
            content: content,
            signature: signature,
            senderPubKeyHex: senderPubKeyHex,
            timestamp: timestamp,
            isMine: false,
          );

          if (!_messages.containsKey(senderPubKeyHex)) {
            _messages[senderPubKeyHex] = [];
          }
          _messages[senderPubKeyHex]!.add(msg);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  void addFriend(String pubKeyHex, String alias) {
    if (!_friends.any((f) => f.pubKeyHex == pubKeyHex)) {
      _friends.add(Friend(pubKeyHex: pubKeyHex, alias: alias));
      notifyListeners();
    }
  }

  void toggleBlacklist(String pubKeyHex) {
    final index = _friends.indexWhere((f) => f.pubKeyHex == pubKeyHex);
    if (index != -1) {
      _friends[index].isBlacklisted = !_friends[index].isBlacklisted;
      notifyListeners();
    }
  }

  void sendMessage(String content, ed.PrivateKey privateKey, String senderPubKeyHex, String targetPubKeyHex) {
    if (!_isConnected) return;

    final messageHash = CryptoUtil.hashMessage(content);
    final signature = CryptoUtil.signMessage(messageHash, privateKey);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final payload = {
      'type': 'chat',
      'content': content,
      'signature': signature,
      'senderPubKeyHex': senderPubKeyHex,
      'targetPubKeyHex': targetPubKeyHex,
      'timestamp': timestamp,
    };

    _channel!.sink.add(jsonEncode(payload));

    final msg = ChatMessage(
      content: content,
      signature: signature,
      senderPubKeyHex: senderPubKeyHex,
      timestamp: timestamp,
      isMine: true,
    );

    if (!_messages.containsKey(targetPubKeyHex)) {
      _messages[targetPubKeyHex] = [];
    }
    _messages[targetPubKeyHex]!.add(msg);
    notifyListeners();
  }
}
