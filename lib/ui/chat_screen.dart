import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hex/hex.dart';
import 'dart:typed_data';
import '../core/chat_provider.dart';
import '../core/crypto_util.dart';
import '../core/wallet_provider.dart';
import '../models/friend.dart';
import 'friend_info_screen.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_message_list.dart';

class ChatScreen extends StatefulWidget {
  final Friend friend;

  const ChatScreen({Key? key, required this.friend}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final wallet = Provider.of<WalletProvider>(
      context,
      listen: false,
    ).activeWallet!;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final seed = Uint8List.fromList(HEX.decode(wallet.seedHex));
    final keyPair = CryptoUtil.deriveKeyPair(seed);

    chatProvider.sendMessage(
      text,
      keyPair.privateKey,
      wallet.agentId,
      widget.friend.pubKeyHex,
    );
    _messageController.clear();
  }

  Future<void> _sendVoiceMessage(String filePath, Duration duration) async {
    final wallet = Provider.of<WalletProvider>(
      context,
      listen: false,
    ).activeWallet!;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final seed = Uint8List.fromList(HEX.decode(wallet.seedHex));
    final keyPair = CryptoUtil.deriveKeyPair(seed);

    await chatProvider.sendVoiceMessage(
      filePath,
      duration,
      keyPair.privateKey,
      wallet.agentId,
      widget.friend.pubKeyHex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);

    // 实时获取最新的好友对象
    final friend = chatProvider.friends.firstWhere(
      (f) => f.pubKeyHex == widget.friend.pubKeyHex,
      orElse: () => widget.friend,
    );

    final messages = chatProvider.messages[friend.pubKeyHex] ?? [];
    final char = friend.alias.isNotEmpty ? friend.alias[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          centerTitle: false,
          backgroundColor: Colors.white,
          elevation: 0.5,
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF00D1C1).withOpacity(0.1),
                child: Text(
                  char,
                  style: const TextStyle(
                    color: Color(0xFF00D1C1),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.alias,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${friend.pubKeyHex.substring(0, 12)}...',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FriendInfoScreen(friend: friend),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ChatMessageList(
                messages: messages,
                scrollController: _scrollController,
                remoteAvatarText: char,
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return ChatComposer(
      controller: _messageController,
      hintText: 'Secure message...',
      onSend: _sendMessage,
      onAttach: () {},
      onMic: () {},
      onSendVoice: _sendVoiceMessage,
    );
  }
}
