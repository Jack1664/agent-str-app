import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chat_provider.dart';
import '../core/crypto_util.dart';
import '../core/wallet_provider.dart';
import '../models/friend.dart';

class ChatScreen extends StatefulWidget {
  final Friend friend;

  const ChatScreen({Key? key, required this.friend}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final wallet = Provider.of<WalletProvider>(context, listen: false).activeWallet!;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Prompt for password to decrypt seed to sign message
    final password = await _promptPassword(context);
    if (password == null || !mounted) return;

    final seed = CryptoUtil.decryptSeed(wallet.encryptedBase64Seed, password);
    if (seed == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Password!')));
      }
      return;
    }

    final keyPair = CryptoUtil.deriveKeyPair(seed);

    chatProvider.sendMessage(text, keyPair.privateKey, wallet.agentId, widget.friend.pubKeyHex);
    _messageController.clear();
  }

  Future<String?> _promptPassword(BuildContext context) {
    String psw = '';
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Unlock Wallet to Sign'),
          content: TextField(
            obscureText: true,
            onChanged: (v) => psw = v,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, psw),
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
    final messages = chatProvider.messages[widget.friend.pubKeyHex] ?? [];
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.friend.alias),
        backgroundColor: Colors.indigo.shade800,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true, // Show latest at bottom
              itemCount: messages.length,
              itemBuilder: (context, index) {
                // Reverse because ListView reverse is true
                final msg = messages[messages.length - 1 - index];
                
                return Align(
                  alignment: msg.isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: msg.isMine ? Colors.indigo.shade100 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(msg.content, style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          'Sig: ${msg.signature.substring(0, 16)}...',
                          style: const TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _sendMessage,
                  child: const Icon(Icons.send),
                  elevation: 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
