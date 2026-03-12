import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../core/crypto_util.dart';
import '../core/wallet_provider.dart';
import '../models/wallet.dart';

class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen({Key? key}) : super(key: key);

  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isGenerating = false;

  void _createWallet() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isGenerating = true);
      
      // Simulate slight delay for UX
      await Future.delayed(const Duration(milliseconds: 500));

      // 1. Generate Seed (Private Key)
      final seed = CryptoUtil.generateSeed();
      
      // 2. Derive ED25519 KeyPair
      final keyPair = CryptoUtil.deriveKeyPair(seed);

      // 3. Get Agent ID (Public Key Hex) and Agent Address (Bech32)
      final agentId = CryptoUtil.getAgentId(keyPair);
      final agentAddress = CryptoUtil.getAgentAddress(agentId);

      // 4. Encrypt seed with password
      final encryptedSeed = CryptoUtil.encryptSeed(seed, _passwordController.text);

      // 5. Create Wallet object and save
      final wallet = Wallet(
        id: const Uuid().v4(),
        name: _nameController.text,
        encryptedBase64Seed: encryptedSeed,
        agentId: agentId,
        agentAddress: agentAddress,
      );

      await Provider.of<WalletProvider>(context, listen: false).addWallet(wallet);

      setState(() => _isGenerating = false);

      if (mounted) {
        Navigator.of(context).pop(); // Return to list
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('New Wallet'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.security_rounded, size: 40, color: Color(0xFF00D1C1)),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Identity Setup',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Set up your ED25519 wallet identity.\nYour password will encrypt your local seed.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 40),

              // Wallet Name Input
              Text(
                'WALLET NAME',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'e.g. Personal Wallet',
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
                validator: (v) => v == null || v.isEmpty ? 'Please enter a name' : null,
              ),

              const SizedBox(height: 24),

              // Password Input
              Text(
                'ENCRYPTION PASSWORD',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Minimum 6 characters',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
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
                validator: (v) => v == null || v.length < 6 ? 'Password must be at least 6 chars' : null,
              ),

              const SizedBox(height: 48),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  backgroundColor: const Color(0xFF1A1A1A),
                ),
                onPressed: _isGenerating ? null : _createWallet,
                child: _isGenerating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Generate & Save Wallet',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
