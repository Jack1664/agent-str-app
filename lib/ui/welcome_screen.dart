import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'main_navigation_screen.dart';
import '../core/notification_service.dart';
import '../core/wallet_provider.dart';
import 'dart:math' as math;

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({Key? key}) : super(key: key);

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    // Load wallets, then navigate
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Provider.of<WalletProvider>(context, listen: false).loadWallets();
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const MainNavigationScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService.processPendingNavigation();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Cyberpunk/AI Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A), // Dark Slate
                  Color(0xFF1E293B), // Slate
                  Color(0xFF0F172A),
                ],
              ),
            ),
          ),

          // Animated Abstract Circuit/AI Lines (Using a CustomPainter)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: BackgroundPainter(_controller.value),
                child: Container(),
              );
            },
          ),

          // Glassmorphism Overlay
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glowing Logo Container
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D1C1).withOpacity(0.3),
                        blurRadius: 40,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome, // AI/Sparkle style
                    size: 80,
                    color: Color(0xFF00D1C1),
                  ),
                ),
                const SizedBox(height: 32),

                // Tech Title
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.white, Color(0xFF00D1C1)],
                  ).createShader(bounds),
                  child: const Text(
                    'AGENT STR',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // AI Subtitle
                Text(
                  'DECENTRALIZED • SECURE • INTELLIGENT',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: Colors.white.withOpacity(0.5),
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 60),

                // Loading Indicator
                const SizedBox(
                  width: 40,
                  height: 2,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF00D1C1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BackgroundPainter extends CustomPainter {
  final double animationValue;
  BackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00D1C1).withOpacity(0.1)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final random = math.Random(42); // Fixed seed for stability

    for (int i = 0; i < 15; i++) {
      double x1 = random.nextDouble() * size.width;
      double y1 = random.nextDouble() * size.height;
      double x2 = x1 + (random.nextDouble() - 0.5) * 200;
      double y2 = y1 + (random.nextDouble() - 0.5) * 200;

      // Animate movement
      double offset = math.sin(animationValue * math.pi * 2 + i) * 20;

      canvas.drawLine(Offset(x1 + offset, y1), Offset(x2 + offset, y2), paint);

      // Draw nodes
      canvas.drawCircle(
        Offset(x1 + offset, y1),
        2,
        paint..style = PaintingStyle.fill,
      );
    }

    // Draw some large abstract circles
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.2),
      100 + math.sin(animationValue * math.pi * 2) * 20,
      paint
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF00D1C1).withOpacity(0.05),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
