import 'dart:io';

import 'package:flutter/services.dart';

class AppBadgeService {
  AppBadgeService._();

  static const MethodChannel _channel = MethodChannel(
    'com.example.agent_str/app_badge',
  );

  static Future<void> updateCount(int count) async {
    if (!Platform.isIOS) return;

    final safeCount = count < 0 ? 0 : count;
    await _channel.invokeMethod<void>('setBadgeCount', {'count': safeCount});
  }

  static Future<void> clear() async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('clearBadge');
  }
}
