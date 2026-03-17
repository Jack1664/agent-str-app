import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hex/hex.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import '../core/chat_provider.dart';
import '../core/crypto_util.dart';
import '../core/wallet_provider.dart';
import '../models/friend.dart';
import '../models/chat_message.dart';
import 'friend_info_screen.dart';
import 'widgets/chat_composer.dart';

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
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 20,
                ),
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[messages.length - 1 - index];
                  return _buildMessageBubble(msg, friend.alias);
                },
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, String alias) {
    if (msg.isSystem) {
      return _buildSystemNotice(msg);
    }

    final bool isMine = msg.isMine;
    final timeStr = DateFormat(
      'HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(msg.timestamp));
    final double maxWidth = MediaQuery.of(context).size.width * 0.75;

    // 头像首字母
    final String avatarChar = alias.isNotEmpty ? alias[0].toUpperCase() : '?';
    // 气泡内 Agent ID 展示
    final String agentIdShort = "Agent ${msg.senderPubKeyHex.substring(0, 8)}";

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end, // 与气泡底部对齐
        children: [
          if (!isMine) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.orange.shade100,
              child: Text(
                avatarChar,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: 6,
              ),
              decoration: BoxDecoration(
                color: isMine ? const Color(0xFF00D1C1) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: isMine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isMine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        agentIdShort,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    msg.content,
                    style: TextStyle(
                      color: isMine ? Colors.white : const Color(0xFF1A1A1A),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: isMine ? Colors.white70 : Colors.grey.shade400,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMine) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildSystemNotice(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE5E5),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFFFB8B8)),
          ),
          child: Text(
            msg.content,
            style: const TextStyle(
              color: Color(0xFFD93025),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
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
