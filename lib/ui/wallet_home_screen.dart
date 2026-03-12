import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chat_provider.dart';
import '../core/wallet_provider.dart';
import '../core/crypto_util.dart';
import 'chat_screen.dart';
import 'add_friend_screen.dart';

class WalletHomeScreen extends StatefulWidget {
  const WalletHomeScreen({Key? key}) : super(key: key);

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen> {
  final _urlController = TextEditingController(text: 'ws://112.126.60.140:8765/ws/agent');
  bool _isAuthDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoConnect();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAuthStatus();
  }

  void _checkAuthStatus() {
    final chatProvider = Provider.of<ChatProvider>(context);
    if (chatProvider.isAuthPending && !_isAuthDialogOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showAuthDialog();
      });
    }
  }

  void _showAuthDialog() {
    if (_isAuthDialogOpen) return;
    _isAuthDialogOpen = true;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final wallet = Provider.of<WalletProvider>(context, listen: false).activeWallet!;
    String password = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Color(0xFF00D1C1)),
            SizedBox(width: 12),
            Text('Identity Challenge', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The relay requires a signature to verify your identity. Enter your wallet password to continue.',
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 24),
            TextField(
              obscureText: true,
              onChanged: (v) => password = v,
              decoration: InputDecoration(
                labelText: 'Wallet Password',
                filled: true,
                fillColor: Colors.grey.shade50,
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _isAuthDialogOpen = false;
              chatProvider.disconnect();
            },
            child: const Text('Disconnect', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final seed = CryptoUtil.decryptSeed(wallet.encryptedBase64Seed, password);
              if (seed != null) {
                Navigator.pop(context);
                final success = await chatProvider.authenticateWithSeed(seed, password);
                _isAuthDialogOpen = false;
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Authentication failed'), behavior: SnackBarBehavior.floating),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid password'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Authenticate'),
          ),
        ],
      ),
    ).then((_) => _isAuthDialogOpen = false);
  }

  void _tryAutoConnect() {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (walletProvider.activeWallet != null) {
      chatProvider.autoConnect(walletProvider.activeWallet!);
    }
  }

  void _connectRelay() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: anim1,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: Row(
              children: [
                const Icon(Icons.cloud_outlined, color: Color(0xFF00D1C1)),
                const SizedBox(width: 12),
                const Text('Connect Relay', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter the WebSocket URL of your messaging relay.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'WebSocket URL',
                    hintText: 'ws://...',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.link, size: 20),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                onPressed: () {
                  final wallet = Provider.of<WalletProvider>(context, listen: false).activeWallet!;
                  Provider.of<ChatProvider>(context, listen: false).connect(_urlController.text, wallet);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Connect'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _addFriendDialog(String pubKeyHex) {
    final aliasController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Add Contact', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${pubKeyHex.substring(0, 16)}...',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: aliasController,
              decoration: InputDecoration(
                labelText: 'Alias / Name',
                hintText: 'How should we call them?',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              if (aliasController.text.isNotEmpty) {
                final walletId = Provider.of<WalletProvider>(context, listen: false).activeWallet!.id;
                Provider.of<ChatProvider>(context, listen: false).addFriend(walletId, pubKeyHex, aliasController.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Friend added to Contacts'), behavior: SnackBarBehavior.floating),
                );
              }
            },
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Save'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = Provider.of<WalletProvider>(context).activeWallet;
    final chatProvider = Provider.of<ChatProvider>(context);

    if (wallet == null) return const Scaffold(body: Center(child: Text('No active wallet.')));

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        toolbarHeight: 70,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Wallet Chat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              '${wallet.name} • ${wallet.agentAddress.substring(0, 8)}...',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              chatProvider.isConnected ? (chatProvider.isAuthenticated ? Icons.cloud_done : Icons.cloud_queue) : Icons.cloud_off,
              color: chatProvider.isAuthenticated ? const Color(0xFF00D1C1) : (chatProvider.isConnected ? Colors.orange : Colors.grey),
            ),
            onPressed: chatProvider.isConnected ? () => chatProvider.disconnect() : _connectRelay,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (!chatProvider.isConnected)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Relay disconnected. Tap cloud icon to connect.',
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          if (chatProvider.isConnected && !chatProvider.isAuthenticated)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Authentication required. Tap cloud icon or wait for prompt.',
                      style: TextStyle(color: Colors.blue.shade800, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: const Color(0xFF00D1C1),
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      tabs: const [
                        Tab(text: 'Friends'),
                        Tab(text: 'Explore'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildFriendsList(chatProvider),
                          _buildTopicsList(chatProvider),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AddFriendScreen()));
        },
        backgroundColor: const Color(0xFF1A1A1A),
        child: const Icon(Icons.person_add_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildFriendsList(ChatProvider chatProvider) {
    if (chatProvider.friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No friends added yet', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: chatProvider.friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final friend = chatProvider.friends[index];
        final char = friend.alias.isNotEmpty ? friend.alias[0].toUpperCase() : (friend.pubKeyHex.isNotEmpty ? friend.pubKeyHex[0].toUpperCase() : '?');

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF00D1C1).withOpacity(0.1),
              child: Text(
                char,
                style: const TextStyle(color: Color(0xFF00D1C1), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(friend.alias, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              friend.isBlacklisted ? 'Blacklisted' : 'Tap to start chat',
              style: TextStyle(fontSize: 12, color: friend.isBlacklisted ? Colors.red : Colors.grey),
            ),
            onTap: () {
              if (!friend.isBlacklisted) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ChatScreen(friend: friend)),
                );
              }
            },
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (value) async {
                final walletId = Provider.of<WalletProvider>(context, listen: false).activeWallet!.id;
                if (value == 'delete') {
                  final confirm = await _showDeleteConfirm(friend.alias);
                  if (confirm == true) {
                    chatProvider.deleteFriend(walletId, friend.pubKeyHex);
                  }
                } else if (value == 'blacklist') {
                  chatProvider.toggleBlacklist(walletId, friend.pubKeyHex);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'blacklist',
                  child: Row(
                    children: [
                      Icon(Icons.block_flipped, size: 20, color: Colors.orange),
                      SizedBox(width: 12),
                      Text('Blacklist'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showDeleteConfirm(String alias) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Contact?'),
        content: Text('Are you sure you want to remove $alias from your friends?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicsList(ChatProvider chatProvider) {
    if (chatProvider.topics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No active topics on relay', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: chatProvider.topics.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final pubKeyHex = chatProvider.topics[index];
        final isFriend = chatProvider.friends.any((f) => f.pubKeyHex == pubKeyHex);

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF1A1A1A),
              child: Icon(Icons.tag, color: Colors.white, size: 18),
            ),
            title: Text(
              '${pubKeyHex.substring(0, 8)}...${pubKeyHex.substring(pubKeyHex.length - 8)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace'),
            ),
            subtitle: const Text('Online Wallet', style: TextStyle(fontSize: 11)),
            trailing: isFriend
                ? const Icon(Icons.check_circle, color: Color(0xFF00D1C1))
                : ElevatedButton(
                    onPressed: () => _addFriendDialog(pubKeyHex),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Add', style: TextStyle(fontSize: 12)),
                  ),
          ),
        );
      },
    );
  }
}
