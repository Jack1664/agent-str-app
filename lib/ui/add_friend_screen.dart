import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chat_provider.dart';
import '../core/wallet_provider.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({Key? key}) : super(key: key);

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _idController = TextEditingController();
  final _aliasController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final walletProvider = Provider.of<WalletProvider>(context, listen: false);
      final activeWallet = walletProvider.activeWallet;

      if (activeWallet != null) {
        final friendAgentId = _idController.text.trim();
        // 1. Save locally using wallet UUID for indexing
        await chatProvider.addFriend(
          activeWallet.id,
          friendAgentId,
          _aliasController.text.trim(),
        );

        // 2. Authorize on Relay using Agent ID (Public Key Hex)
        if (chatProvider.isAuthenticated) {
          // Corrected: Use activeWallet.agentId instead of activeWallet.id
          await chatProvider.allowAgent(activeWallet.agentId, friendAgentId);
        }

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Friend added and authorized successfully'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF00D1C1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Add Friend'),
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const Icon(Icons.person_add_outlined, size: 80, color: Color(0xFF00D1C1)),
                const SizedBox(height: 16),
                const Text(
                  'Add New Contact',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the Agent ID and a nickname for your friend.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 40),

                // Agent ID Input
                _buildInputLabel('AGENT ID (HEX)'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _idController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. 75a5749a...',
                    prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFF00D1C1), width: 1.5),
                    ),
                  ),
                  validator: (v) => v == null || v.length < 4 ? 'Please enter a valid ID' : null,
                ),

                const SizedBox(height: 24),

                // Alias Input
                _buildInputLabel('ALIAS / NICKNAME'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _aliasController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Alice Smith',
                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFF00D1C1), width: 1.5),
                    ),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Alias is required' : null,
                ),

                const SizedBox(height: 48),

                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: const Color(0xFF1A1A1A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 4,
                    shadowColor: Colors.black26,
                  ),
                  child: const Text(
                    'Save & Authorize Contact',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade500,
        letterSpacing: 1.2,
      ),
    );
  }
}
