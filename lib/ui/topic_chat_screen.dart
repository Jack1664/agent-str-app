import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chat_provider.dart';
import '../core/crypto_util.dart';
import '../core/wallet_provider.dart';
import '../models/chat_message.dart';
import 'topic_info_screen.dart';

class TopicChatScreen extends StatefulWidget {
  final TopicInfo topic;

  const TopicChatScreen({Key? key, required this.topic}) : super(key: key);

  @override
  State<TopicChatScreen> createState() => _TopicChatScreenState();
}

class _TopicChatScreenState extends State<TopicChatScreen> {
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final wallet = Provider.of<WalletProvider>(context, listen: false).activeWallet!;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // 1. Check if we have a cached password from the Challenge auth
    String? password = chatProvider.tempPassword;

    // 2. If no cache, prompt user
    if (password == null) {
      password = await _promptPassword(context);
    }

    if (password == null || !mounted) return;

    final seed = CryptoUtil.decryptSeed(wallet.encryptedBase64Seed, password);
    if (seed == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid Password!'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    final keyPair = CryptoUtil.deriveKeyPair(seed);
    // For topics, the identifier in _messages is the full topic ID (topic:name)
    chatProvider.sendMessage(
      text,
      keyPair.privateKey,
      wallet.agentId,
      widget.topic.id,
      chatType: "topic"
    );
    _messageController.clear();
  }

  Future<String?> _promptPassword(BuildContext context) {
    String psw = '';
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: const Text('Confirm Identity', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your password to sign this message with your private key.',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 20),
              TextField(
                obscureText: true,
                autofocus: true,
                onChanged: (v) => psw = v,
                decoration: InputDecoration(
                  labelText: 'Wallet Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, psw),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Sign & Send'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);

    // Find the current topic info from provider to react to alias changes
    final topic = chatProvider.myTopics.firstWhere(
      (t) => t.id == widget.topic.id,
      orElse: () => widget.topic,
    );

    final messages = chatProvider.messages[topic.id] ?? [];
    final char = topic.alias.isNotEmpty ? topic.alias[0].toUpperCase() : '#';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF1A1A1A).withOpacity(0.1),
              child: Text(char, style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic.alias, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    topic.id,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontFamily: 'monospace'),
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
                MaterialPageRoute(builder: (_) => TopicInfoScreen(topic: topic)),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[messages.length - 1 - index];
                return _buildMessageBubble(msg);
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final bool isMine = msg.isMine;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                'Agent: ${msg.senderPubKeyHex.substring(0, 8)}...',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
              ),
            ),
          Row(
            mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMine ? const Color(0xFF1A1A1A) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMine ? 20 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Text(
                    msg.content,
                    style: TextStyle(
                      color: isMine ? Colors.white : const Color(0xFF1A1A1A),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.only(left: isMine ? 0 : 8, right: isMine ? 8 : 0),
            child: Text(
              'SIG: ${msg.signature.length > 8 ? msg.signature.substring(0, 8) : msg.signature}...',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade400, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FA),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Message topic...',
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              height: 48,
              width: 48,
              decoration: const BoxDecoration(
                color: Color(0xFF00D1C1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}
