import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/friend.dart';
import '../ui/chat_screen.dart';
import '../ui/topic_chat_screen.dart';
import 'chat_provider.dart';
import 'wallet_provider.dart';

class NotificationService {
  NotificationService._();

  static const String _pendingPayloadKey = 'pending_notification_payload';

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _mainNavigationReady = false;
  static bool _isAppInForeground = true;
  static String? _pendingPayload;

  static bool get hasPendingNavigation =>
      _pendingPayload != null && _pendingPayload!.isNotEmpty;
  static bool get isAppInForeground => _isAppInForeground;

  static void setMainNavigationReady(bool ready) {
    _mainNavigationReady = ready;
  }

  static void setAppInForeground(bool isForeground) {
    _isAppInForeground = isForeground;
  }

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
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
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
    _pendingPayload ??= await _readPersistedPendingPayload();

    _initialized = true;
  }

  static Future<void> showIncomingMessage({
    required String title,
    required String body,
    int? badgeCount,
    String? payload,
  }) async {
    await initialize();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'Messages',
        channelDescription: 'Notifications for incoming chat messages',
        importance: Importance.high,
        priority: Priority.high,
        number: badgeCount,
      ),
      iOS: DarwinNotificationDetails(badgeNumber: badgeCount),
      macOS: DarwinNotificationDetails(badgeNumber: badgeCount),
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
    if (!_mainNavigationReady) return;
    final payload = _pendingPayload;
    final navigated = await _navigateFromPayload(payload);
    if (navigated) {
      _pendingPayload = null;
      await _clearPersistedPendingPayload();
    }
  }

  static Future<void> _handleNotificationTap(String? payload) async {
    _pendingPayload = payload;
    await _persistPendingPayload(payload);
    await Future.delayed(const Duration(milliseconds: 350));
    await processPendingNavigation();
  }

  static Future<void> _persistPendingPayload(String? payload) async {
    final prefs = await SharedPreferences.getInstance();
    if (payload == null || payload.isEmpty) {
      await prefs.remove(_pendingPayloadKey);
      return;
    }
    await prefs.setString(_pendingPayloadKey, payload);
  }

  static Future<String?> _readPersistedPendingPayload() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingPayloadKey);
  }

  static Future<void> _clearPersistedPendingPayload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingPayloadKey);
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

      navigator.popUntil((route) => route.isFirst);

      if (chatType == 'topic') {
        final topic =
            chatProvider.myTopics.cast<TopicInfo?>().firstWhere(
              (item) => item?.id == peerId,
              orElse: () => null,
            ) ??
            TopicInfo(id: peerId, title: title.isNotEmpty ? title : peerId);
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

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  final payload = response.payload;
  final prefs = await SharedPreferences.getInstance();
  if (payload == null || payload.isEmpty) {
    await prefs.remove(NotificationService._pendingPayloadKey);
    return;
  }
  await prefs.setString(NotificationService._pendingPayloadKey, payload);
}
