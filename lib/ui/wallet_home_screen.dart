import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chat_provider.dart';
import '../core/wallet_provider.dart';
import '../core/crypto_util.dart';
import '../models/wallet.dart';
import '../models/friend.dart';
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
        surfaceTintColor: Colors.transparent,
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
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _isAuthDialogOpen = false;
                    chatProvider.disconnect();
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Disconnect', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
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
                    backgroundColor: const Color(0xFF00D1C1),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Authenticate', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
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

  void _showConnectionStatus(ChatProvider chatProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF00D1C1)),
            SizedBox(width: 12),
            Text('Relay Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusItem('Status', chatProvider.isConnected ? (chatProvider.isAuthenticated ? 'Connected & Verified' : 'Connected (Pending Auth)') : 'Disconnected',
              color: chatProvider.isAuthenticated ? Colors.green : (chatProvider.isConnected ? Colors.orange : Colors.red)),
            const SizedBox(height: 16),
            _buildStatusItem('Relay URL', chatProvider.lastUsedUrl ?? 'N/A'),
            if (chatProvider.isAuthenticated) ...[
              const SizedBox(height: 16),
              _buildStatusItem('Active Agent', '${chatProvider.lastUsedWallet?.agentId.substring(0, 16)}...'),
            ]
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    chatProvider.disconnect();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Disconnect', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color ?? const Color(0xFF1A1A1A))),
      ],
    );
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
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            title: const Row(
              children: [
                Icon(Icons.cloud_outlined, color: Color(0xFF00D1C1)),
                const SizedBox(width: 12),
                Text('Connect Relay', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                        final wallet = Provider.of<WalletProvider>(context, listen: false).activeWallet!;
                        Provider.of<ChatProvider>(context, listen: false).connect(_urlController.text.trim(), wallet);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A1A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
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
        surfaceTintColor: Colors.transparent,
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
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D1C1),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
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
          if (chatProvider.isConnecting)
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00D1C1))),
            )
          else
            IconButton(
              icon: Icon(
                chatProvider.isConnected ? (chatProvider.isAuthenticated ? Icons.cloud_done : Icons.cloud_queue) : Icons.cloud_off,
                color: chatProvider.isAuthenticated ? const Color(0xFF00D1C1) : (chatProvider.isConnected ? Colors.orange : Colors.grey),
              ),
              onPressed: chatProvider.isConnected ? () => _showConnectionStatus(chatProvider) : _connectRelay,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (chatProvider.isConnecting)
            LinearProgressIndicator(backgroundColor: Colors.transparent, color: const Color(0xFF00D1C1).withOpacity(0.5)),
          if (!chatProvider.isConnected && !chatProvider.isConnecting)
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
                length: 3,
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
                        Tab(text: 'Topics'),
                        Tab(text: 'Explore'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildFriendsTab(chatProvider, wallet),
                          _buildTopicsList(chatProvider),
                          _buildExploreList(chatProvider),
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

  Widget _buildFriendsTab(ChatProvider chatProvider, Wallet activeWallet) {
    final pending = chatProvider.pendingRequests;
    final friends = [...chatProvider.friends];

    // 置顶排序逻辑
    friends.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return 0;
    });

    if (pending.isEmpty && friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No friends added yet', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (pending.isNotEmpty) ...[
          const Text(
            'PENDING REQUESTS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),
          ...pending.map((req) => _buildPendingRequestItem(req, chatProvider, activeWallet)),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
        ],
        if (friends.isNotEmpty) ...[
          const Text(
            'YOUR FRIENDS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),
          ...friends.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildFriendItem(entry.value, chatProvider),
              )),
        ],
      ],
    );
  }

  Widget _buildPendingRequestItem(FriendRequest req, ChatProvider chatProvider, Wallet activeWallet) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF00D1C1).withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00D1C1).withOpacity(0.2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF00D1C1),
          child: const Icon(Icons.person_add, color: Colors.white, size: 20),
        ),
        title: Text(
          'Request: ${req.senderPubKey.substring(0, 8)}...',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            req.content,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle, color: Color(0xFF00D1C1)),
              onPressed: () => chatProvider.acceptRequest(activeWallet.id, activeWallet.agentId, req.senderPubKey),
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
              onPressed: () => chatProvider.rejectRequest(req.senderPubKey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendItem(Friend friend, ChatProvider chatProvider) {
    final char = friend.alias.isNotEmpty ? friend.alias[0].toUpperCase() : (friend.pubKeyHex.isNotEmpty ? friend.pubKeyHex[0].toUpperCase() : '?');

    return Container(
      decoration: BoxDecoration(
        color: friend.isPinned ? const Color(0xFF00D1C1).withOpacity(0.03) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(20),
        border: friend.isPinned ? Border.all(color: const Color(0xFF00D1C1).withOpacity(0.1)) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF00D1C1).withOpacity(0.1),
              child: Text(
                char,
                style: const TextStyle(color: Color(0xFF00D1C1), fontWeight: FontWeight.bold),
              ),
            ),
            if (friend.isPinned)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Color(0xFF00D1C1), shape: BoxShape.circle),
                  child: const Icon(Icons.push_pin_rounded, size: 10, color: Colors.white),
                ),
              ),
          ],
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
            } else if (value == 'pin') {
              chatProvider.toggleFriendPin(walletId, friend.pubKeyHex);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'pin',
              child: Row(
                children: [
                  Icon(friend.isPinned ? Icons.push_pin_outlined : Icons.push_pin, size: 20, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text(friend.isPinned ? 'Unpin' : 'Pin to Top'),
                ],
              ),
            ),
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
  }

  Future<bool?> _showDeleteConfirm(String alias) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Contact?'),
        content: Text('Are you sure you want to remove $alias from your friends?'),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopicsList(ChatProvider chatProvider) {
    if (chatProvider.myTopics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No topics subscribed', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: chatProvider.myTopics.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final topic = chatProvider.myTopics[index];
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF1A1A1A),
              child: const Icon(Icons.tag, color: Colors.white, size: 18),
            ),
            title: Text(topic.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Tap to open chat', style: TextStyle(fontSize: 12, color: Colors.grey)),
            onTap: () {
              // TODO: 跳转到 Topic 聊天页面
            },
          ),
        );
      },
    );
  }

  Widget _buildExploreList(ChatProvider chatProvider) {
    if (chatProvider.discoveredTopics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No active topics on relay', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: chatProvider.discoveredTopics.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final topicId = chatProvider.discoveredTopics[index];
        final isSubscribed = chatProvider.myTopics.any((t) => t.id == topicId);

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
              topicId.startsWith("topic:") ? topicId.substring(6) : topicId,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            trailing: isSubscribed
                ? const Icon(Icons.check_circle, color: Color(0xFF00D1C1))
                : ElevatedButton(
                    onPressed: () {
                      final wallet = Provider.of<WalletProvider>(context, listen: false).activeWallet!;
                      chatProvider.subscribeTopic(wallet.id, wallet.agentId, topicId.startsWith("topic:") ? topicId.substring(6) : topicId);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      minimumSize: const Size(0, 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Join', style: TextStyle(fontSize: 12)),
                  ),
          ),
        );
      },
    );
  }
}
