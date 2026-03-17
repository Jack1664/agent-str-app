import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:hex/hex.dart';
import 'dart:typed_data';
import '../core/crypto_util.dart';
import '../core/wallet_provider.dart';
import '../core/chat_provider.dart';
import '../models/wallet.dart';
import 'widgets/top_notice.dart';

class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen({Key? key}) : super(key: key);

  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isProcessing = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  void _saveWallet() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isProcessing = true);

      try {
        await Future.delayed(const Duration(milliseconds: 500));

        Uint8List seed;
        if (_tabController.index == 0) {
          // Mode: Create New
          seed = CryptoUtil.generateSeed();
        } else {
          // Mode: Import
          final hexStr = _privateKeyController.text.trim().replaceAll(
            RegExp(r'\s+'),
            '',
          );
          seed = Uint8List.fromList(HEX.decode(hexStr));
        }

        final keyPair = CryptoUtil.deriveKeyPair(seed);
        final agentId = CryptoUtil.getAgentId(keyPair);
        final agentAddress = CryptoUtil.getAgentAddress(agentId);
        final seedHex = HEX.encode(seed);

        final wallet = Wallet(
          id: const Uuid().v4(),
          name: _nameController.text,
          seedHex: seedHex,
          agentId: agentId,
          agentAddress: agentAddress,
        );

        final walletProvider = Provider.of<WalletProvider>(
          context,
          listen: false,
        );
        await walletProvider.addWallet(wallet);

        // Also auto-connect the chat provider for the new wallet
        if (mounted) {
          Provider.of<ChatProvider>(context, listen: false).autoConnect(wallet);
        }

        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        TopNotice.show('Error: ${e.toString()}', backgroundColor: Colors.red);
      } finally {
        if (mounted) setState(() => _isProcessing = false);
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00D1C1),
          labelColor: const Color(0xFF1A1A1A),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Create New'),
            Tab(text: 'Import Private Key'),
          ],
        ),
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
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 40,
                    color: Color(0xFF00D1C1),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Wallet Name Input
              _buildLabel('WALLET NAME'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _nameController,
                hint: 'e.g. My Secure Wallet',
                icon: Icons.badge_outlined,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Please enter a name' : null,
              ),

              const SizedBox(height: 20),

              // Conditional Private Key Input
              AnimatedBuilder(
                animation: _tabController,
                builder: (context, child) {
                  if (_tabController.index == 1) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('PRIVATE KEY (HEX)'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _privateKeyController,
                          hint: '64 character hex string',
                          icon: Icons.vpn_key_outlined,
                          maxLines: 3,
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'Enter your private key';
                            final cleaned = v.trim().replaceAll(
                              RegExp(r'\s+'),
                              '',
                            );
                            if (cleaned.length != 64)
                              return 'Private key must be 64 characters';
                            try {
                              HEX.decode(cleaned);
                            } catch (e) {
                              return 'Invalid hex string';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              const SizedBox(height: 40),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  backgroundColor: const Color(0xFF00D1C1),
                ),
                onPressed: _isProcessing ? null : _saveWallet,
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _tabController.index == 0
                            ? 'Generate & Save'
                            : 'Import & Save',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),

              const SizedBox(height: 16),
              Text(
                'Your keys are stored locally on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade500,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 && !obscure ? 40 : 0),
          child: Icon(icon, size: 20),
        ),
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
      validator: validator,
    );
  }
}
