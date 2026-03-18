import 'package:flutter/material.dart';
import '../core/notification_service.dart';
import 'chats_page.dart';
import 'explore_screen.dart';
import 'settings_screen.dart';
import 'widgets/liquid_glass_tab_bar.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  static const double _tabBarVisualHeight = 88;
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const ChatsPage(),
    const ExploreScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.processPendingNavigation();
    });
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final bodyBottomPadding =
        _tabBarVisualHeight + (bottomInset > 0 ? bottomInset : 16);

    return Scaffold(
      extendBody: true,
      body: Padding(
        padding: EdgeInsets.only(bottom: bodyBottomPadding),
        child: IndexedStack(index: _selectedIndex, children: _pages),
      ),
      bottomNavigationBar: LiquidGlassTabBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          LiquidTabItem(
            label: 'Chats',
            icon: Icons.chat_bubble_outline_rounded,
            activeIcon: Icons.chat_bubble_rounded,
          ),
          LiquidTabItem(
            label: 'Explore',
            icon: Icons.explore_outlined,
            activeIcon: Icons.explore_rounded,
          ),
          LiquidTabItem(
            label: 'Settings',
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
          ),
        ],
      ),
    );
  }
}
