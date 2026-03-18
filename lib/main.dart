import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/wallet_provider.dart';
import 'core/chat_provider.dart';
import 'core/notification_service.dart';
import 'ui/welcome_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: const AgentStrApp(),
    ),
  );
}

class AgentStrApp extends StatefulWidget {
  const AgentStrApp({Key? key}) : super(key: key);

  @override
  State<AgentStrApp> createState() => _AgentStrAppState();
}

class _AgentStrAppState extends State<AgentStrApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.setAppInForeground(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.processPendingNavigation();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NotificationService.setAppInForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService.processPendingNavigation();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      title: 'Agent Str',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF00D1C1), // Teal accent from Bitget
        scaffoldBackgroundColor: const Color(
          0xFFF6F8FA,
        ), // Light grey/blue background
        useMaterial3: true,
        fontFamily: 'SF Pro Display', // Typical iOS/Modern look
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Color(0xFF1A1A1A),
          centerTitle: true,
          systemOverlayStyle: SystemUiOverlayStyle.dark, // 设置状态栏图标和文字为黑色
          titleTextStyle: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00D1C1),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
      home: const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark, // 确保初始页面也是黑色
        child: Welcome_Screen_Wrapper(),
      ),
    );
  }
}

class Welcome_Screen_Wrapper extends StatelessWidget {
  const Welcome_Screen_Wrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const WelcomeScreen();
  }
}
