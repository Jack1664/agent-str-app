import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

class LiquidTabItem {
  const LiquidTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class LiquidGlassTabBar extends StatefulWidget {
  const LiquidGlassTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.height = 72,
    this.horizontalPadding = 24,
  }) : assert(
         items.length > 1,
         'LiquidGlassTabBar requires at least two items.',
       );

  final List<LiquidTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double height;
  final double horizontalPadding;

  @override
  State<LiquidGlassTabBar> createState() => _LiquidGlassTabBarState();
}

class _LiquidGlassTabBarState extends State<LiquidGlassTabBar>
    with SingleTickerProviderStateMixin {
  static const _barRadius = 32.0;
  static const _pillHorizontalInset = 14.0;
  static const _pillVerticalInset = 7.0;

  late final AnimationController _indicatorController;
  int? _pressedIndex;

  @override
  void initState() {
    super.initState();
    _indicatorController = AnimationController.unbounded(vsync: this);
    _indicatorController.value = widget.currentIndex.toDouble();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _animateIndicator(
        from: _indicatorController.value,
        to: widget.currentIndex.toDouble(),
      );
    }
  }

  @override
  void dispose() {
    _indicatorController.dispose();
    super.dispose();
  }

  void _animateIndicator({required double from, required double to}) {
    _indicatorController.stop();
    _indicatorController.value = from;
    final simulation = SpringSimulation(
      const SpringDescription(mass: 0.85, stiffness: 170, damping: 18),
      from,
      to,
      0,
    );
    _indicatorController.animateWith(simulation);
  }

  Future<void> _handleTap(int index) async {
    if (index != widget.currentIndex) {
      widget.onTap(index);
    }

    if (_pressedIndex != index) {
      setState(() => _pressedIndex = index);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (mounted && _pressedIndex == index) {
        setState(() => _pressedIndex = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.padding.bottom;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeColor = const Color(0xFF00D1C1);
    final inactiveColor = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final overlayColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.16);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.42);
    final outerShadow = Colors.black.withValues(alpha: isDark ? 0.24 : 0.14);
    final totalHeight = widget.height + (bottomInset > 0 ? bottomInset : 16);

    return SizedBox(
      height: totalHeight,
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.horizontalPadding,
          right: widget.horizontalPadding,
          bottom: bottomInset > 0 ? bottomInset : 16,
        ),
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_barRadius),
              boxShadow: [
                BoxShadow(
                  color: outerShadow,
                  blurRadius: 28,
                  spreadRadius: -6,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: isDark ? 0.03 : 0.3),
                  blurRadius: 12,
                  spreadRadius: -8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_barRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  height: widget.height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_barRadius),
                    border: Border.all(color: borderColor, width: 1),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        overlayColor,
                        overlayColor.withValues(alpha: overlayColor.a * 0.72),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _LiquidGlassShellPainter(isDark: isDark),
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _indicatorController,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: _IndicatorPainter(
                              position: _indicatorController.value.clamp(
                                0,
                                widget.items.length - 1,
                              ),
                              itemCount: widget.items.length,
                              isDark: isDark,
                            ),
                            child: child,
                          );
                        },
                        child: const SizedBox.expand(),
                      ),
                      Row(
                        children: List.generate(widget.items.length, (index) {
                          final item = widget.items[index];
                          final isSelected = index == widget.currentIndex;
                          final isPressed = _pressedIndex == index;

                          return Expanded(
                            child: _LiquidTabButton(
                              item: item,
                              isSelected: isSelected,
                              isPressed: isPressed,
                              activeColor: activeColor,
                              inactiveColor: inactiveColor,
                              onTap: () => _handleTap(index),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidTabButton extends StatelessWidget {
  const _LiquidTabButton({
    required this.item,
    required this.isSelected,
    required this.isPressed,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final LiquidTabItem item;
  final bool isSelected;
  final bool isPressed;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = isPressed ? 0.9 : (isSelected ? 1.0 : 0.94);
    final color = isSelected ? activeColor : inactiveColor;

    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      );
                    },
                    child: Icon(
                      isSelected ? item.activeIcon : item.icon,
                      key: ValueKey<bool>(isSelected),
                      color: color,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      letterSpacing: 0.15,
                      color: color,
                    ),
                    child: Text(item.label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IndicatorPainter extends CustomPainter {
  const _IndicatorPainter({
    required this.position,
    required this.itemCount,
    required this.isDark,
  });

  final double position;
  final int itemCount;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (itemCount <= 0) return;

    final itemWidth = size.width / itemCount;
    final pillWidth =
        itemWidth - (_LiquidGlassTabBarState._pillHorizontalInset * 2);
    final pillHeight =
        size.height - (_LiquidGlassTabBarState._pillVerticalInset * 2);
    final left =
        (position * itemWidth) + _LiquidGlassTabBarState._pillHorizontalInset;
    const top = _LiquidGlassTabBarState._pillVerticalInset;
    final rect = Rect.fromLTWH(left, top, pillWidth, pillHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.08);
    final baseTint = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFEEF1F5).withValues(alpha: 0.82);

    final shadowPaint = Paint()
      ..color = shadowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRRect(rrect.shift(const Offset(0, 8)), shadowPaint);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.18 : 0.72),
          baseTint,
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, fillPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.28 : 0.66),
          Colors.white.withValues(alpha: isDark ? 0.08 : 0.18),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.5), borderPaint);

    final glossRect = Rect.fromLTWH(
      rect.left + 10,
      rect.top + 6,
      rect.width - 20,
      rect.height * 0.32,
    );
    final glossPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.16 : 0.42),
          Colors.white.withValues(alpha: 0.01),
        ],
      ).createShader(glossRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(glossRect, const Radius.circular(18)),
      glossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _IndicatorPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.itemCount != itemCount ||
        oldDelegate.isDark != isDark;
  }
}

class _LiquidGlassShellPainter extends CustomPainter {
  const _LiquidGlassShellPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = BorderRadius.circular(
      _LiquidGlassTabBarState._barRadius,
    ).toRRect(rect);

    final innerGlow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.18 : 0.32),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0, 0.22],
      ).createShader(rect);
    canvas.drawRRect(radius, innerGlow);

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.20 : 0.45),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawRRect(radius.deflate(0.5), highlightPaint);

    final noisePaint = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.030 : 0.045)
      ..strokeWidth = 1;
    for (var i = 0; i < 42; i++) {
      final dx = (size.width / 41) * i;
      final dy = 10 + ((math.sin(i * 1.7) + 1) * 0.5 * (size.height - 20));
      canvas.drawPoints(PointMode.points, [Offset(dx, dy)], noisePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassShellPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
