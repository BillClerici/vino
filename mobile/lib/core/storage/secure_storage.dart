import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../config/constants.dart';

// Conditional import for web sessionStorage
import 'web_storage_stub.dart' if (dart.library.html) 'web_storage_web.dart'
    as web_storage;

class SecureStorageService {
  final FlutterSecureStorage? _storage;

  SecureStorageService()
      : _storage = kIsWeb ? null : const FlutterSecureStorage();

  Future<String?> getAccessToken() => _read(StorageKeys.accessToken);

  Future<String?> getRefreshToken() => _read(StorageKeys.refreshToken);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _write(StorageKeys.accessToken, accessToken);
    await _write(StorageKeys.refreshToken, refreshToken);
  }

  Future<void> clearTokens() async {
    await _delete(StorageKeys.accessToken);
    await _delete(StorageKeys.refreshToken);
  }

  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<String?> _read(String key) async {
    if (_storage != null) {
      return _storage.read(key: key);
    }
    return web_storage.read(key);
  }

  Future<void> _write(String key, String value) async {
    if (_storage != null) {
      await _storage.write(key: key, value: value);
    } else {
      web_storage.write(key, value);
    }
  }

  Future<void> _delete(String key) async {
    if (_storage != null) {
      await _storage.delete(key: key);
    } else {
      web_storage.delete(key);
    }
  }
}
