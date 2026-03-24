import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

/// Top-level background message handler (must be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] Background message: ${message.messageId}');
}

/// Manages Firebase Cloud Messaging — initialization, permissions, token
/// lifecycle, and foreground/background notification handling.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  // Lazily initialized — avoids accessing Firebase on web
  FirebaseMessaging? _messaging;
  FirebaseMessaging get messaging => _messaging ??= FirebaseMessaging.instance;

  final _localNotifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'vino_default';
  static const _channelName = 'Trip Me Notifications';
  static const _channelDesc = 'Trip reminders, friend check-ins, and more';

  /// Initialize Firebase, create notification channel, request permissions.
  Future<void> initialize() async {
    if (_initialized) return;

    // Create Android notification channel
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);

    // Initialize local notifications for foreground display
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Request permission (Android 13+ requires runtime permission)
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _initialized = true;
  }

  /// Get the current FCM device token.
  Future<String?> getToken() async {
    try {
      return await messaging.getToken();
    } catch (e) {
      debugPrint('[FCM] Failed to get token: $e');
      return null;
    }
  }

  /// Listen for token refresh events.
  void onTokenRefresh(void Function(String token) callback) {
    messaging.onTokenRefresh.listen(callback);
  }

  /// Set up message handlers that navigate via GoRouter on notification tap.
  void setupMessageHandlers(GoRouter router) {
    // Foreground messages — show a local notification
    FirebaseMessaging.onMessage.listen((message) {
      _showForegroundNotification(message);
    });

    // Background tap — app was in background, user tapped notification
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _navigateFromMessage(message.data, router);
    });

    // Terminated tap — app was killed, launched from notification
    messaging.getInitialMessage().then((message) {
      if (message != null) {
        _navigateFromMessage(message.data, router);
      }
    });
  }

  /// Show a local notification when a message arrives while the app is in the foreground.
  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Handle taps on local notifications (foreground ones).
  void _onLocalNotificationTap(NotificationResponse response) {
    // Payload contains the FCM data as JSON
    // Navigation will be handled when the app processes the tap
    debugPrint('[FCM] Local notification tapped: ${response.payload}');
  }

  /// Navigate to the appropriate screen based on notification data.
  void _navigateFromMessage(Map<String, dynamic> data, GoRouter router) {
    final route = data['route'] as String?;
    if (route != null && route.isNotEmpty) {
      debugPrint('[FCM] Navigating to: $route');
      router.go(route);
    }
  }
}
