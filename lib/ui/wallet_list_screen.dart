import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/wallet_provider.dart';
import 'create_wallet_screen.dart';
import 'wallet_home_screen.dart';
import 'wallet_detail_screen.dart';

class WalletListScreen extends StatelessWidget {
  const WalletListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);
    final wallets = walletProvider.wallets;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text('My Wallets'),
        centerTitle: true,
      ),
      body: wallets.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                      ),
                      child: Icon(Icons.account_balance_wallet_outlined, size: 64, color: const Color(0xFF00D1C1).withOpacity(0.5)),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'No Wallets Found',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Create your first ED25519 wallet to start secure messaging.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00D1C1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CreateWalletScreen()),
                          );
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline_rounded, size: 22),
                            SizedBox(width: 8),
                            Text('Create New Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), // Extra bottom padding for FAB
              itemCount: wallets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final wallet = wallets[index];
                return GestureDetector(
                  onTap: () {
                    walletProvider.setActiveWallet(wallet);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WalletHomeScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D1C1).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00D1C1), size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                wallet.name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${wallet.agentAddress.substring(0, 8)}...${wallet.agentAddress.substring(wallet.agentAddress.length - 8)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.settings_outlined, size: 18, color: Colors.grey.shade400),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => WalletDetailScreen(wallet: wallet),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: wallets.isNotEmpty
          ? Container(
              height: 60,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D1C1),
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shadowColor: const Color(0xFF00D1C1).withOpacity(0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreateWalletScreen()),
                  );
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 24),
                    SizedBox(width: 8),
                    Text('Create Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
