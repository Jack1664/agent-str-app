import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import '../models/friend.dart';
import '../ui/chat_screen.dart';
import '../ui/topic_chat_screen.dart';
import 'chat_provider.dart';
import 'wallet_provider.dart';

class NotificationService {
  NotificationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String? _pendingPayload;

  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) async {
        await _handleNotificationTap(response.payload);
      },
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    const channel = AndroidNotificationChannel(
      'messages',
      'Messages',
      description: 'Notifications for incoming chat messages',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingPayload = launchDetails?.notificationResponse?.payload;
    }

    _initialized = true;
  }

  static Future<void> showIncomingMessage({
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'Messages',
        channelDescription: 'Notifications for incoming chat messages',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  static Future<void> processPendingNavigation() async {
    if (_pendingPayload == null) return;
    final payload = _pendingPayload;
    final navigated = await _navigateFromPayload(payload);
    if (navigated) {
      _pendingPayload = null;
    }
  }

  static Future<void> _handleNotificationTap(String? payload) async {
    _pendingPayload = payload;
    await Future.delayed(const Duration(milliseconds: 350));
    await processPendingNavigation();
  }

  static Future<bool> _navigateFromPayload(String? payload) async {
    if (payload == null || payload.isEmpty) return false;
    final context = navigatorKey.currentContext;
    final navigator = navigatorKey.currentState;
    if (context == null || navigator == null) return false;

    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    if (walletProvider.activeWallet == null) return false;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final chatType = data['chat_type'] as String? ?? 'dm';
      final peerId = data['peer_id'] as String? ?? '';
      final title = data['title'] as String? ?? '';
      if (peerId.isEmpty) return false;

      if (chatType == 'topic') {
        final topic = chatProvider.myTopics.cast<TopicInfo?>().firstWhere(
          (item) => item?.id == peerId,
          orElse: () => null,
        );
        if (topic == null) return false;
        navigator.push(
          MaterialPageRoute(builder: (_) => TopicChatScreen(topic: topic)),
        );
        return true;
      }

      final friend =
          chatProvider.friends.cast<Friend?>().firstWhere(
            (item) => item?.pubKeyHex == peerId,
            orElse: () => null,
          ) ??
          Friend(
            pubKeyHex: peerId,
            alias: title.isNotEmpty
                ? title
                : (peerId.length > 8 ? peerId.substring(0, 8) : peerId),
          );

      navigator.push(
        MaterialPageRoute(builder: (_) => ChatScreen(friend: friend)),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
