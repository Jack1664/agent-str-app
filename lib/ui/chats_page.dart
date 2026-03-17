import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/chat_provider.dart';
import '../core/wallet_provider.dart';
import '../models/chat_message.dart';
import '../models/friend.dart';
import 'chat_screen.dart';
import 'add_friend_screen.dart';
import 'topic_chat_screen.dart';
import 'wallet_list_screen.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({Key? key}) : super(key: key);

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final _urlController = TextEditingController();
  final _agentsUrlController = TextEditingController();
  final _topicsUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoConnect();
    });
  }

  void _tryAutoConnect() {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    if (walletProvider.activeWallet != null) {
      chatProvider.autoConnect(walletProvider.activeWallet!);
    }
  }

  void _showConnectionStatus(ChatProvider chatProvider) {
    _urlController.text = chatProvider.lastUsedUrl;
    _agentsUrlController.text = chatProvider.agentsUrl;
    _topicsUrlController.text = chatProvider.topicsUrl;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Row(
          children: [
            Icon(Icons.settings_outlined, color: Color(0xFF00D1C1)),
            SizedBox(width: 12),
            Text(
              'Relay & API Config',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusItem(
                'Status',
                chatProvider.isConnected
                    ? (chatProvider.isAuthenticated
                          ? 'Connected & Verified'
                          : 'Connected (Pending Auth)')
                    : 'Disconnected',
                color: chatProvider.isAuthenticated
                    ? Colors.green
                    : (chatProvider.isConnected ? Colors.orange : Colors.red),
              ),
              const SizedBox(height: 20),
              _buildInputLabel('RELAY WEBSOCKET URL'),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: ChatProvider.defaultRelayUrl,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildInputLabel('EXPLORE AGENTS API'),
              const SizedBox(height: 8),
              TextField(
                controller: _agentsUrlController,
                decoration: InputDecoration(
                  hintText: 'http://...',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildInputLabel('EXPLORE TOPICS API'),
              const SizedBox(height: 8),
              TextField(
                controller: _topicsUrlController,
                decoration: InputDecoration(
                  hintText: 'http://...',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final wallet = Provider.of<WalletProvider>(
                      context,
                      listen: false,
                    ).activeWallet!;
                    // Update explore URLs
                    await chatProvider.updateExploreUrls(
                      wallet.agentId,
                      _agentsUrlController.text.trim(),
                      _topicsUrlController.text.trim(),
                    );
                    // Reconnect if URL changed or currently disconnected
                    if (_urlController.text.trim().isNotEmpty) {
                      await chatProvider.connect(
                        _urlController.text.trim(),
                        wallet,
                      );
                    }
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D1C1),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Connect',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade500,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildStatusItem(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade500,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color ?? const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  void _connectRelay() {
    // Reuse the same status dialog for initial connection as well since it now contains all config
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    _showConnectionStatus(chatProvider);
  }

  @override
  Widget build(BuildContext context) {
    final walletProvider = Provider.of<WalletProvider>(context);
    final wallet = walletProvider.activeWallet;
    final chatProvider = Provider.of<ChatProvider>(context);

    if (wallet == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F8FA),
        appBar: AppBar(
          title: const Text(
            'Chats',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        body: Center(
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
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 64,
                    color: Color(0xFF00D1C1),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'No Wallet Found',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please create or import a wallet to start messaging.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D1C1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WalletListScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Go to My Wallets',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            chatProvider.isConnected
                ? (chatProvider.isAuthenticated
                      ? Icons.cloud_done
                      : Icons.cloud_queue)
                : Icons.cloud_off,
            color: chatProvider.isAuthenticated
                ? const Color(0xFF00D1C1)
                : (chatProvider.isConnected ? Colors.orange : Colors.grey),
          ),
          onPressed: () => _showConnectionStatus(chatProvider),
        ),
        title: const Text(
          'Chats',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddFriendScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (chatProvider.isConnecting)
            LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              color: const Color(0xFF00D1C1).withOpacity(0.5),
            ),

          Expanded(
            child: _buildCombinedList(chatProvider, wallet.id, wallet.agentId),
          ),
        ],
      ),
    );
  }

  Widget _buildCombinedList(
    ChatProvider chatProvider,
    String walletId,
    String agentId,
  ) {
    final pending = chatProvider.pendingRequests;
    final friends = chatProvider.friends;
    final topics = chatProvider.myTopics;

    if (pending.isEmpty && friends.isEmpty && topics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            const Text('No chats yet', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddFriendScreen()),
              ),
              child: const Text('Add Friend or Topic'),
            ),
          ],
        ),
      );
    }

    // Combine friends and topics into a single list
    List<dynamic> combinedList = [];
    combinedList.addAll(friends);
    combinedList.addAll(topics);

    // Sorting (Pins first, then maybe timestamp/name)
    combinedList.sort((a, b) {
      bool aPinned = (a is Friend) ? a.isPinned : false;
      bool bPinned = (b is Friend) ? b.isPinned : false;
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return 0;
    });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: pending.length + combinedList.length,
      itemBuilder: (context, index) {
        if (index < pending.length) {
          return _buildPendingRequestItem(
            pending[index],
            chatProvider,
            walletId,
            agentId,
          );
        }
        final item = combinedList[index - pending.length];
        if (item is Friend) {
          final latestMessage = _getLatestMessagePreview(
            chatProvider.messages[item.pubKeyHex],
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildFriendItem(
              item,
              chatProvider,
              walletId,
              latestMessage: latestMessage,
            ),
          );
        } else {
          final latestMessage = _getLatestMessagePreview(
            chatProvider.messages[item.id],
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildTopicItem(
              item,
              chatProvider,
              latestMessage: latestMessage,
            ),
          );
        }
      },
    );
  }

  Widget _buildPendingRequestItem(
    FriendRequest req,
    ChatProvider chatProvider,
    String walletId,
    String agentId,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF00D1C1).withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00D1C1).withOpacity(0.2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFF00D1C1),
          child: Icon(Icons.person_add, color: Colors.white, size: 20),
        ),
        title: Text(
          'Friend Request: ${req.senderPubKey.substring(0, 8)}...',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          req.content,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle, color: Color(0xFF00D1C1)),
              onPressed: () => chatProvider.acceptRequest(
                walletId,
                agentId,
                req.senderPubKey,
              ),
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

  String? _getLatestMessagePreview(List<ChatMessage>? messages) {
    if (messages == null || messages.isEmpty) return null;

    final latest = messages.last;
    final content = latest.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (content.isEmpty) return null;
    return latest.isMine ? 'You: $content' : content;
  }

  Widget _buildFriendItem(
    Friend friend,
    ChatProvider chatProvider,
    String walletId, {
    String? latestMessage,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF00D1C1).withOpacity(0.1),
              child: Text(
                friend.alias.isNotEmpty ? friend.alias[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Color(0xFF00D1C1),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (friend.isPinned)
              Positioned(
                right: 0,
                bottom: 0,
                child: Icon(Icons.push_pin, size: 12, color: Colors.orange),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                friend.alias,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Friend',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          latestMessage ?? '${friend.pubKeyHex.substring(0, 12)}...',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatScreen(friend: friend)),
        ),
        onLongPress: () =>
            _showFriendMenu(context, friend, chatProvider, walletId),
      ),
    );
  }

  Widget _buildTopicItem(
    TopicInfo topic,
    ChatProvider chatProvider, {
    String? latestMessage,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple.shade50,
          child: const Icon(Icons.tag, color: Colors.purple, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                topic.alias,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Topic',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.purple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          latestMessage ?? 'Group Conversation',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TopicChatScreen(topic: topic)),
        ),
      ),
    );
  }

  void _showFriendMenu(
    BuildContext context,
    Friend friend,
    ChatProvider chatProvider,
    String walletId,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                friend.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
              ),
              title: Text(friend.isPinned ? 'Unpin' : 'Pin to Top'),
              onTap: () {
                chatProvider.toggleFriendPin(walletId, friend.pubKeyHex);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete Contact',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                chatProvider.deleteFriend(walletId, friend.pubKeyHex);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
