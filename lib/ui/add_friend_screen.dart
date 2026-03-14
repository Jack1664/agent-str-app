import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  final _messageController = TextEditingController(text: "Hi, I'd like to add you as a friend");
  final _topicController = TextEditingController();
  final _topicAliasController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isScanning = false;
  int _selectedTab = 0; // 0: Friend, 1: Topic

  void _submitFriend() async {
    if (_formKey.currentState!.validate()) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final walletProvider = Provider.of<WalletProvider>(context, listen: false);
      final activeWallet = walletProvider.activeWallet;

      if (activeWallet != null) {
        final friendAgentId = _idController.text.trim();
        final requestMessage = _messageController.text.trim();

        await chatProvider.addFriend(
          activeWallet.id,
          friendAgentId,
          _aliasController.text.trim(),
        );

        if (chatProvider.isAuthenticated) {
          await chatProvider.allowAgent(activeWallet.agentId, friendAgentId);

          if (requestMessage.isNotEmpty) {
            await chatProvider.sendFriendRequest(
              activeWallet.agentId,
              friendAgentId,
              requestMessage,
            );
          }
        }

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Friend request sent and authorized'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF00D1C1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    }
  }

  void _submitTopic() async {
    final topicName = _topicController.text.trim();
    final topicAlias = _topicAliasController.text.trim();

    if (topicName.isEmpty) return;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final activeWallet = walletProvider.activeWallet;

    if (activeWallet != null) {
      await chatProvider.subscribeTopic(
        activeWallet.id,
        activeWallet.agentId,
        topicName,
        alias: topicAlias.isNotEmpty ? topicAlias : null,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscribed to topic: ${topicAlias.isNotEmpty ? topicAlias : topicName}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF00D1C1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _toggleScanner() {
    setState(() {
      _isScanning = !_isScanning;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: Text(_selectedTab == 0 ? 'Add Friend' : 'Join Topic'),
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Segmented Toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTabButton(0, 'Friend', Icons.person_add_alt_1),
                    ),
                    Expanded(
                      child: _buildTabButton(1, 'Topic', Icons.tag),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              IndexedStack(
                index: _selectedTab,
                children: [
                  _buildAddFriendForm(),
                  _buildAddTopicForm(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddFriendForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isScanning)
            _buildScannerView()
          else
            const Column(
              children: [
                Icon(Icons.person_add_outlined, size: 64, color: Color(0xFF00D1C1)),
                SizedBox(height: 12),
                Text('Add New Friend', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          const SizedBox(height: 30),
          _buildInputLabel('AGENT ID (HEX)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _idController,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. 75a5749a...',
              prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
              suffixIcon: Padding(
                padding: const EdgeInsets.all(12.0),
                child: GestureDetector(
                  onTap: _toggleScanner,
                  child: SvgPicture.asset(
                    'assets/images/scan.svg',
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(Color(0xFF00D1C1), BlendMode.srcIn),
                  ),
                ),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00D1C1), width: 1.5)),
            ),
            validator: (v) => v == null || v.length != 64 ? 'Agent ID must be 64 characters' : null,
          ),
          const SizedBox(height: 24),
          _buildInputLabel('ALIAS / NICKNAME'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _aliasController,
            decoration: InputDecoration(
              hintText: 'e.g. Alice',
              prefixIcon: const Icon(Icons.badge_outlined, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00D1C1), width: 1.5)),
            ),
            validator: (v) => v == null || v.isEmpty ? 'Alias is required' : null,
          ),
          const SizedBox(height: 24),
          _buildInputLabel('REQUEST MESSAGE'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _messageController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Introduction...',
              prefixIcon: const Icon(Icons.chat_bubble_outline, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00D1C1), width: 1.5)),
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: _submitFriend,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Send Friend Request', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddTopicForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: Column(
            children: [
              Icon(Icons.tag, size: 64, color: Color(0xFF00D1C1)),
              SizedBox(height: 12),
              Text('Subscribe to Topic', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Join a group conversation by topic ID', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 40),
        _buildInputLabel('TOPIC NAME / ID'),
        const SizedBox(height: 8),
        TextField(
          controller: _topicController,
          decoration: InputDecoration(
            hintText: 'e.g. general, development...',
            prefixIcon: const Icon(Icons.tag, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00D1C1), width: 1.5)),
          ),
        ),
        const SizedBox(height: 24),
        _buildInputLabel('ALIAS / NICKNAME'),
        const SizedBox(height: 8),
        TextField(
          controller: _topicAliasController,
          decoration: InputDecoration(
            hintText: 'e.g. My Favorite Group',
            prefixIcon: const Icon(Icons.badge_outlined, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF00D1C1), width: 1.5)),
          ),
        ),
        const SizedBox(height: 48),
        ElevatedButton(
          onPressed: _submitTopic,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: const Text('Subscribe & Join', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildScannerView() {
    return Column(
      children: [
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? code = barcodes.first.rawValue;
                if (code != null && code.trim().length == 64) {
                  setState(() {
                    _idController.text = code.trim();
                    _isScanning = false;
                  });
                }
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _toggleScanner,
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Cancel Scan'),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
        ),
      ],
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.2),
    );
  }
}
