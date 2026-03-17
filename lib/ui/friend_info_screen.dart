import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/friend.dart';
import '../core/chat_provider.dart';
import '../core/wallet_provider.dart';

class FriendInfoScreen extends StatefulWidget {
  final Friend friend;
  const FriendInfoScreen({Key? key, required this.friend}) : super(key: key);

  @override
  State<FriendInfoScreen> createState() => _FriendInfoScreenState();
}

class _FriendInfoScreenState extends State<FriendInfoScreen> {
  late TextEditingController _aliasController;
  bool _isPinned = false;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController(text: widget.friend.alias);
    _isPinned = widget.friend.isPinned;
  }

  void _save() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    if (walletProvider.activeWallet == null) return;
    final walletId = walletProvider.activeWallet!.id;

    if (_aliasController.text != widget.friend.alias) {
      await chatProvider.updateFriendAlias(walletId, widget.friend.pubKeyHex, _aliasController.text.trim());
    }

    if (_isPinned != widget.friend.isPinned) {
      await chatProvider.toggleFriendPin(walletId, widget.friend.pubKeyHex);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Friend info updated'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF00D1C1),
        ),
      );
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Are you sure you want to delete ${widget.friend.alias}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final chatProvider = Provider.of<ChatProvider>(context, listen: false);
              final walletProvider = Provider.of<WalletProvider>(context, listen: false);
              if (walletProvider.activeWallet != null) {
                await chatProvider.deleteFriend(walletProvider.activeWallet!.id, widget.friend.pubKeyHex);
                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmBlacklist() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.friend.isBlacklisted ? 'Unblock Contact' : 'Block Contact'),
        content: Text(widget.friend.isBlacklisted
          ? 'Do you want to unblock ${widget.friend.alias}?'
          : 'Are you sure you want to block ${widget.friend.alias}? You will no longer receive messages from them.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final chatProvider = Provider.of<ChatProvider>(context, listen: false);
              final walletProvider = Provider.of<WalletProvider>(context, listen: false);
              if (walletProvider.activeWallet != null) {
                await chatProvider.toggleBlacklist(walletProvider.activeWallet!.id, widget.friend.pubKeyHex);
                if (mounted) {
                  Navigator.pop(context);
                  Navigator.pop(context);
                }
              }
            },
            child: Text(widget.friend.isBlacklisted ? 'Unblock' : 'Block', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return "$y-$m-$d $h:$min";
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatTimestamp(widget.friend.createdAt);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Friend Info'),
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
                backgroundColor: const Color(0xFF00D1C1).withOpacity(0.1),
                child: Text(
                  widget.friend.alias.isNotEmpty ? widget.friend.alias[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 32, color: Color(0xFF00D1C1), fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 32),

            _buildLabel('ALIAS'),
            const SizedBox(height: 8),
            TextField(
              controller: _aliasController,
              decoration: InputDecoration(
                hintText: 'Enter nickname',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),

            const SizedBox(height: 24),

            _buildLabel('AGENT ID'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText(
                widget.friend.pubKeyHex,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black54),
              ),
            ),

            const SizedBox(height: 24),
            _buildLabel('ADDED AT'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(dateStr, style: const TextStyle(color: Colors.black87)),
            ),

            const SizedBox(height: 32),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Pin to Top', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: const Text('Keep this chat at the top of the list', style: TextStyle(fontSize: 12)),
                    value: _isPinned,
                    activeColor: const Color(0xFF00D1C1),
                    onChanged: (v) => setState(() => _isPinned = v),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.block_flipped, color: Colors.orange),
                    title: Text(widget.friend.isBlacklisted ? 'Unblock Contact' : 'Block Contact', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w500)),
                    onTap: _confirmBlacklist,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                    title: const Text('Delete Contact', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                    onTap: _confirmDelete,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
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
