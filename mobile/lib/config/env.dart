import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

class EnvConfig {
  static const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// On web/Chrome, default to localhost. On mobile (Android emulator), use 10.0.2.2.
  static String get apiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
    return kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000';
  }

  /// Google Maps API key — fetched from the server config endpoint and cached.
  static String _googleMapsApiKey = const String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  static String get googleMapsApiKey => _googleMapsApiKey;

  static const stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  /// Deep link scheme for OAuth callbacks
  static const deepLinkScheme = 'vino';

  /// Fetch remote config (call once on app startup).
  static Future<void> loadRemoteConfig() async {
    if (_googleMapsApiKey.isNotEmpty) return; // Already set via --dart-define
    try {
      final dio = Dio(BaseOptions(baseUrl: apiBaseUrl));
      final resp = await dio.get('/api/v1/config/');
      final data = resp.data;
      // Handle envelope wrapper
      final config = data is Map && data.containsKey('data')
          ? data['data'] as Map<String, dynamic>
          : data as Map<String, dynamic>;
      _googleMapsApiKey = config['google_maps_api_key'] as String? ?? '';
      debugPrint('[EnvConfig] Google Maps key loaded: ${_googleMapsApiKey.isNotEmpty}');
    } catch (e) {
      debugPrint('[EnvConfig] Failed to load remote config: $e');
    }
  }
}
