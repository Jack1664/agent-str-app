import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hex/hex.dart';
import '../models/wallet.dart';
import '../core/crypto_util.dart';
import '../core/wallet_provider.dart';

class WalletDetailScreen extends StatefulWidget {
  final Wallet wallet;

  const WalletDetailScreen({Key? key, required this.wallet}) : super(key: key);

  @override
  State<WalletDetailScreen> createState() => _WalletDetailScreenState();
}

class _WalletDetailScreenState extends State<WalletDetailScreen> {
  final _passwordController = TextEditingController();
  String? _decryptedPrivateKeyHex; // This will now store the 32-byte Seed
  bool _isDecrypting = false;

  void _showPrivateKeyDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Security Verification', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your wallet password to reveal the private key.',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    _passwordController.clear();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final password = _passwordController.text;
                    Navigator.pop(context);
                    _decryptAndShow(password);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _decryptAndShow(String password) {
    setState(() => _isDecrypting = true);

    // Decrypt the seed
    final seed = CryptoUtil.decryptSeed(widget.wallet.encryptedBase64Seed, password);

    if (seed != null) {
      // Consistent with Python: show the 32-byte seed as the Private Key
      setState(() {
        _decryptedPrivateKeyHex = HEX.encode(seed);
        _isDecrypting = false;
      });
      _passwordController.clear();
    } else {
      setState(() => _isDecrypting = false);
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid password'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF00D1C1),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Wallet?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'This action cannot be undone. Make sure you have backed up your private key.',
          style: TextStyle(color: Colors.black54),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Provider.of<WalletProvider>(context, listen: false).deleteWallet(widget.wallet.id);
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context); // Back to wallet list
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
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
        title: const Text('Wallet Details'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            onPressed: _confirmDelete,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFF00D1C1),
                        child: Icon(Icons.wallet_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        widget.wallet.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Network',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const Text(
                    'Agent Str Main Network ',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('Agent ID (Public Key)'),
            const SizedBox(height: 12),
            _buildDataCard(
              content: widget.wallet.agentId,
              onCopy: () => _copyToClipboard(widget.wallet.agentId, 'Agent ID'),
              color: Colors.white,
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Agent Address (Bech32)'),
            const SizedBox(height: 12),
            _buildDataCard(
              content: widget.wallet.agentAddress,
              onCopy: () => _copyToClipboard(widget.wallet.agentAddress, 'Agent Address'),
              color: Colors.white,
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('Private Key (Seed)', isDanger: true),
            const SizedBox(height: 12),
            if (_decryptedPrivateKeyHex == null)
              _buildRevealCard()
            else
              _buildDataCard(
                content: _decryptedPrivateKeyHex!,
                onCopy: () => _copyToClipboard(_decryptedPrivateKeyHex!, 'Private Key'),
                color: Colors.red.shade50,
                isPrivate: true,
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool isDanger = false}) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: isDanger ? Colors.red.shade400 : Colors.grey.shade500,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildDataCard({
    required String content,
    required VoidCallback onCopy,
    required Color color,
    bool isPrivate = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        border: isPrivate ? Border.all(color: Colors.red.shade100) : null,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  content,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCopy,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.copy_rounded, size: 20, color: Color(0xFF1A1A1A)),
                ),
              ),
            ],
          ),
          if (isPrivate) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Never share your private key. It provides full access to your identity.',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildRevealCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_person_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'Private key is encrypted',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          const Text(
            'Authentication is required to view',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isDecrypting ? null : _showPrivateKeyDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D1C1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isDecrypting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Reveal Private Key'),
          ),
        ],
      ),
    );
  }
}
