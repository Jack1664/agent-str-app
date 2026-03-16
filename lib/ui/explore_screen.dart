import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../core/chat_provider.dart';
import '../core/wallet_provider.dart';
import '../models/friend.dart';

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
        final response = await http.get(Uri.parse('http://112.126.60.140:8765/api/agents'));
        if (response.statusCode == 200) {
          if (mounted) {
            final data = json.decode(response.body);
            List<dynamic> agents = data['items'] ?? [];

            // 排序：在线的排在前面
            agents.sort((a, b) {
              bool onlineA = a['online'] ?? false;
              bool onlineB = b['online'] ?? false;
              if (onlineA == onlineB) return 0;
              return onlineA ? -1 : 1;
            });

            setState(() {
              _agents = agents;
            });
          }
        }
      } else {
        final response = await http.get(Uri.parse('http://112.126.60.140:8765/api/topics'));
        if (response.statusCode == 200) {
          if (mounted) {
            final data = json.decode(response.body);
            setState(() {
              _topics = data['items'] ?? [];
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
      final agentId = agent['agent_id'] ?? agent['id'];
      final name = agent['name'] ?? 'Agent ${agentId.toString().substring(0, 6)}';

      await chatProvider.addFriend(activeWallet.id, agentId, name);

      if (chatProvider.isAuthenticated) {
        await chatProvider.allowAgent(activeWallet.agentId, agentId);
        await chatProvider.sendFriendRequest(
          activeWallet.agentId,
          agentId,
          "Hi, I'd like to add you as a friend (from Explore)",
        );
      }

      if (mounted) {
        Fluttertoast.showToast(
          msg: "Friend request sent to $name",
          gravity: ToastGravity.TOP,
          backgroundColor: const Color(0xFF00D1C1),
          textColor: Colors.white,
        );
      }
    }
  }

  void _subscribeTopic(Map<String, dynamic> topic) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final activeWallet = walletProvider.activeWallet;

    if (activeWallet != null) {
      final topicId = topic['topic_id'] ?? topic['id'] ?? '';
      final topicName = topic['title'] ?? topic['name'] ?? topicId;

      await chatProvider.subscribeTopic(
        activeWallet.id,
        activeWallet.agentId,
        topicId,
        alias: topicName,
      );

      if (mounted) {
        Fluttertoast.showToast(
          msg: "Subscribed to topic: $topicName",
          gravity: ToastGravity.TOP,
          backgroundColor: const Color(0xFF00D1C1),
          textColor: Colors.white,
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
    final chatProvider = Provider.of<ChatProvider>(context);
    final friends = chatProvider.friends;

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
        final id = agent['agent_id'] ?? agent['id'] ?? '';
        final name = agent['name'] ?? 'Agent ${id.toString().substring(0, 6)}';
        final bool isOnline = agent['online'] ?? false;

        // 检查是否已经是好友
        Friend? existingFriend;
        try {
          existingFriend = friends.firstWhere((f) => f.pubKeyHex == id);
        } catch (_) {
          existingFriend = null;
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Stack(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF00D1C1).withOpacity(0.1),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Color(0xFF00D1C1), fontWeight: FontWeight.bold),
                  ),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 8),
                if (isOnline)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('ONLINE', style: TextStyle(color: Colors.green, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            subtitle: Text(
              id.length > 16 ? '${id.substring(0, 16)}...' : id,
              style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
            ),
            trailing: existingFriend != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Added', style: TextStyle(color: Color(0xFF00D1C1), fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(
                        DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(existingFriend.createdAt)),
                        style: const TextStyle(color: Colors.grey, fontSize: 9),
                      ),
                    ],
                  )
                : ElevatedButton(
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
    final chatProvider = Provider.of<ChatProvider>(context);
    final myTopics = chatProvider.myTopics;

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
        final id = topic['topic_id'] ?? topic['id'] ?? '';
        final name = topic['title'] ?? topic['name'] ?? 'Topic';
        final subCount = topic['subscriber_count'] ?? 0;
        final msgCount = topic['message_count'] ?? 0;

        // 检查是否已经订阅
        final bool isSubscribed = myTopics.any((t) => t.id == id);

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
              '$subCount subscribers • $msgCount messages',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            trailing: isSubscribed
                ? const Text('Subscribed', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))
                : ElevatedButton(
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
