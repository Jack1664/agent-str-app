import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chat_provider.dart';
import '../core/wallet_provider.dart';

class TopicInfoScreen extends StatefulWidget {
  final TopicInfo topic;
  const TopicInfoScreen({Key? key, required this.topic}) : super(key: key);

  @override
  State<TopicInfoScreen> createState() => _TopicInfoScreenState();
}

class _TopicInfoScreenState extends State<TopicInfoScreen> {
  late TextEditingController _aliasController;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController(text: widget.topic.alias);
  }

  void _save() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    if (walletProvider.activeWallet == null) return;
    final walletId = walletProvider.activeWallet!.id;

    if (_aliasController.text != widget.topic.alias) {
      await chatProvider.updateTopicAlias(walletId, widget.topic.id, _aliasController.text.trim());
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Topic alias updated'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF00D1C1),
        ),
      );
    }
  }

  void _confirmUnsubscribe() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Unsubscribe Topic?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to leave ${widget.topic.alias}? You will no longer receive messages from this topic.'),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
                    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
                    final activeWallet = walletProvider.activeWallet;

                    if (activeWallet != null) {
                      await chatProvider.unsubscribeTopic(activeWallet.id, activeWallet.agentId, widget.topic.id);
                      if (mounted) {
                        Navigator.pop(context); // Close dialog
                        Navigator.pop(context); // Exit Info screen
                        Navigator.pop(context); // Exit Chat screen
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Unsubscribe', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Topic Details'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF1A1A1A).withOpacity(0.1),
                child: Text(
                  widget.topic.alias.isNotEmpty ? widget.topic.alias[0].toUpperCase() : '#',
                  style: const TextStyle(fontSize: 32, color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 32),

            _buildLabel('TOPIC ID'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                widget.topic.id,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: Colors.black54),
              ),
            ),

            const SizedBox(height: 24),

            _buildLabel('ALIAS / NICKNAME'),
            const SizedBox(height: 8),
            TextField(
              controller: _aliasController,
              decoration: InputDecoration(
                hintText: 'Enter nickname for this topic',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),

            const SizedBox(height: 48),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D1C1),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _confirmUnsubscribe,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Unsubscribe Topic', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade500,
        letterSpacing: 1,
      ),
    );
  }
}
