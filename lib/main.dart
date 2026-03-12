import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/wallet_provider.dart';
import 'core/chat_provider.dart';
import 'ui/welcome_screen.dart';

void main() {
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

class AgentStrApp extends StatelessWidget {
  const AgentStrApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agent Str',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF00D1C1), // Teal accent from Bitget
        scaffoldBackgroundColor: const Color(0xFFF6F8FA), // Light grey/blue background
        useMaterial3: true,
        fontFamily: 'SF Pro Display', // Typical iOS/Modern look
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Color(0xFF1A1A1A),
          centerTitle: true,
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      home: const Welcome_Screen_Wrapper(),
    );
  }
}

class Welcome_Screen_Wrapper extends StatelessWidget {
  const Welcome_Screen_Wrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Check if we already have wallets to decide where to start
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    return const WelcomeScreen();
  }
}
