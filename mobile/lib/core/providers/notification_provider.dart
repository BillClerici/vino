import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/constants.dart';
import '../api/api_client.dart';
import '../auth/auth_provider.dart';
import '../services/notification_service.dart';

/// Provider that manages FCM token registration with the backend.
/// Automatically registers when user logs in, unregisters on logout.
final notificationSetupProvider = Provider<void>((ref) {
  final authState = ref.watch(authStateProvider);
  final api = ref.read(apiClientProvider);
  final service = NotificationService();

  authState.whenData((user) async {
    if (user != null && !kIsWeb) {
      // User logged in — register FCM token (mobile only)
      try {
        await service.initialize();
        final token = await service.getToken();
        if (token != null) {
          await _registerToken(api, token);
        }

        // Listen for token refreshes
        service.onTokenRefresh((newToken) async {
          await _registerToken(api, newToken);
        });
      } catch (e) {
        debugPrint('[Notifications] Setup failed: $e');
      }
    }
  });
});

Future<void> _registerToken(ApiClient api, String token) async {
  try {
    await api.post(ApiPaths.deviceTokenRegister, data: {
      'token': token,
      'device_type': 'android',
    });
    debugPrint('[Notifications] FCM token registered');
  } catch (e) {
    debugPrint('[Notifications] Token registration failed: $e');
  }
}

/// Call this on logout to unregister the device token.
Future<void> unregisterDeviceToken(ApiClient api) async {
  try {
    final token = await NotificationService().getToken();
    if (token != null) {
      await api.post(ApiPaths.deviceTokenUnregister, data: {'token': token});
      debugPrint('[Notifications] FCM token unregistered');
    }
  } catch (e) {
    debugPrint('[Notifications] Token unregister failed: $e');
  }
}
