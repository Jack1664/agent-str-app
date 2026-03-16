import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../core/chat_provider.dart';
import '../core/wallet_provider.dart';

class ExploreWidget extends StatefulWidget {
  const ExploreWidget({Key? key}) : super(key: key);

  @override
  State<ExploreWidget> createState() => _ExploreWidgetState();
}

class _ExploreWidgetState extends State<ExploreWidget> {
  int _selectedTab = 0; // 0: Friend, 1: Topic
  bool _isLoading = false;
  List<dynamic> _agents = [];
  List<dynamic> _topics = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (_selectedTab == 0) {
        final response = await http.get(Uri.parse('https://lobs.cc/api/agents'));
        if (response.statusCode == 200) {
          if (mounted) {
            setState(() {
              _agents = json.decode(response.body);
            });
          }
        }
      } else {
        final response = await http.get(Uri.parse('https://lobs.cc/api/topics'));
        if (response.statusCode == 200) {
          if (mounted) {
            setState(() {
              _topics = json.decode(response.body);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _addFriend(Map<String, dynamic> agent) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final activeWallet = walletProvider.activeWallet;

    if (activeWallet != null) {
      final agentId = agent['id'];
      final name = agent['name'] ?? 'Unknown Agent';

      // 1. Add to local friends list
      await chatProvider.addFriend(activeWallet.id, agentId, name);

      if (chatProvider.isAuthenticated) {
        // 2. Allow agent (ACL)
        await chatProvider.allowAgent(activeWallet.agentId, agentId);

        // 3. Send friend request message
        await chatProvider.sendFriendRequest(
          activeWallet.agentId,
          agentId,
          "Hi, I'd like to add you as a friend (from Explore)",
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend request sent to $name'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF00D1C1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _subscribeTopic(Map<String, dynamic> topic) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final activeWallet = walletProvider.activeWallet;

    if (activeWallet != null) {
      final topicId = topic['id'];
      final topicName = topic['name'] ?? topicId;

      await chatProvider.subscribeTopic(
        activeWallet.id,
        activeWallet.agentId,
        topicId,
        alias: topicName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscribed to topic: $topicName'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF00D1C1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(0, 'Friend', Icons.people_outline),
                ),
                Expanded(
                  child: _buildTabButton(1, 'Topic', Icons.tag),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D1C1)))
              : RefreshIndicator(
                  onRefresh: _fetchData,
                  color: const Color(0xFF00D1C1),
                  child: _selectedTab == 0 ? _buildAgentList() : _buildTopicList(),
                ),
        ),
      ],
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        if (_selectedTab != index) {
          setState(() {
            _selectedTab = index;
            _agents = [];
            _topics = [];
          });
          _fetchData();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFF1A1A1A) : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentList() {
    if (_agents.isEmpty && !_isLoading) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Column(
              children: [
                Icon(Icons.people_outline, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text('No agents found', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _agents.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final agent = _agents[index];
        final name = agent['name'] ?? 'Agent';
        final id = agent['id'] ?? '';

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
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: Color(0xFF00D1C1), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              id.length > 16 ? '${id.substring(0, 16)}...' : id,
              style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
            ),
            trailing: ElevatedButton(
              onPressed: () => _addFriend(agent),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D1C1),
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(60, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Add', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopicList() {
    if (_topics.isEmpty && !_isLoading) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Column(
              children: [
                Icon(Icons.tag, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text('No topics found', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _topics.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final topic = _topics[index];
        final name = topic['name'] ?? 'Topic';
        final id = topic['id'] ?? '';

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
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              id,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            trailing: ElevatedButton(
              onPressed: () => _subscribeTopic(topic),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(80, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Subscribe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        );
      },
    );
  }
}
