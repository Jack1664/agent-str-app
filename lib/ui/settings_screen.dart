import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/wallet_provider.dart';
import '../core/chat_provider.dart';
import '../models/wallet.dart';
import 'wallet_list_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  void _showWalletSelector(BuildContext context, WalletProvider walletProvider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Switch Wallet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: walletProvider.wallets.length,
                  itemBuilder: (context, index) {
                    final wallet = walletProvider.wallets[index];
                    final bool isActive = walletProvider.activeWallet?.id == wallet.id;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isActive ? const Color(0xFF00D1C1) : Colors.grey.shade200,
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          color: isActive ? Colors.white : Colors.grey.shade500,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        wallet.name,
                        style: TextStyle(
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          color: isActive ? const Color(0xFF00D1C1) : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        '${wallet.agentAddress.substring(0, 8)}...${wallet.agentAddress.substring(wallet.agentAddress.length - 8)}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                      trailing: isActive
                          ? const Icon(Icons.check_circle, color: Color(0xFF00D1C1))
                          : null,
                      onTap: () {
                        walletProvider.setActiveWallet(wallet);
                        // Also auto-connect the chat provider for the new wallet
                        Provider.of<ChatProvider>(context, listen: false).autoConnect(wallet);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Manage Wallets'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WalletListScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);
    final activeWallet = walletProvider.activeWallet;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (activeWallet != null)
            Card(
              child: InkWell(
                onTap: () => _showWalletSelector(context, walletProvider),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF00D1C1).withOpacity(0.1),
                      child: const Icon(Icons.person, color: Color(0xFF00D1C1)),
                    ),
                    title: Text(activeWallet.name),
                    subtitle: Text(
                      '${activeWallet.agentAddress.substring(0, 8)}...${activeWallet.agentAddress.substring(activeWallet.agentAddress.length - 8)}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    trailing: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          _buildSettingsItem(
            context,
            icon: Icons.account_balance_wallet_outlined,
            title: 'My Wallets',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WalletListScreen()),
              );
            },
          ),
          _buildSettingsItem(
            context,
            icon: Icons.security_outlined,
            title: 'Security',
            onTap: () {
              // TODO: Security settings
            },
          ),
          _buildSettingsItem(
            context,
            icon: Icons.help_outline_rounded,
            title: 'Help & Support',
            onTap: () {
              // TODO: Help
            },
          ),
          _buildSettingsItem(
            context,
            icon: Icons.info_outline_rounded,
            title: 'About',
            onTap: () {
              // TODO: About
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF00D1C1)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        onTap: onTap,
      ),
    );
  }
}
