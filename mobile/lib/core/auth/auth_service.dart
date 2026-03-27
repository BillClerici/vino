import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/constants.dart';
import '../api/api_client.dart';
import '../models/user.dart';
import '../storage/secure_storage.dart';

class AuthService {
  final ApiClient _api;
  final SecureStorageService _storage;

  AuthService(this._api, this._storage);

  /// DEV ONLY: Log in without OAuth by hitting the dev-login endpoint.
  Future<User> devLogin({String? email}) async {
    final resp = await _api.post(
      '/api/v1/auth/dev-login/',
      data: email != null ? {'email': email} : {},
    );

    final data = resp.data['data'] as Map<String, dynamic>;
    await _storage.saveTokens(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );

    return getProfile();
  }

  Future<User> signInWithGoogle() async {
    final clientId = const String.fromEnvironment('GOOGLE_CLIENT_ID');
    if (clientId.isEmpty) {
      throw Exception('GOOGLE_CLIENT_ID not set — rebuild APK with --dart-define=GOOGLE_CLIENT_ID=...');
    }
    final googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
      serverClientId: clientId,
    );

    debugPrint('[GoogleAuth] Starting sign-in...');
    final account = await googleSignIn.signIn()
        .timeout(const Duration(seconds: 15));
    if (account == null) throw Exception('Google sign-in cancelled');
    debugPrint('[GoogleAuth] Account selected: ${account.email}');

    debugPrint('[GoogleAuth] Getting authentication tokens...');
    final auth = await account.authentication
        .timeout(const Duration(seconds: 10));
    debugPrint('[GoogleAuth] Got tokens. idToken=${auth.idToken != null}, serverAuthCode=${account.serverAuthCode != null}');

    final authCode = account.serverAuthCode;
    final idToken = auth.idToken;

    if (authCode == null && idToken == null) {
      throw Exception('No auth credentials received from Google');
    }

    debugPrint('[GoogleAuth] Posting to backend...');
    final resp = await _api.post(
      '${ApiPaths.auth}/google/',
      data: {
        if (authCode != null) 'auth_code': authCode,
        if (idToken != null) 'id_token': idToken,
      },
    );

    final data = resp.data['data'] as Map<String, dynamic>;
    await _storage.saveTokens(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );

    debugPrint('[GoogleAuth] Sign-in complete');
    return getProfile();
  }

  Future<User> signInWithMicrosoft() async {
    // Uses flutter_web_auth_2 for WebView-based OAuth
    // The Django backend handles the full OAuth flow and redirects to
    // vino://auth/callback with tokens
    final result = await _launchMicrosoftAuth();

    await _storage.saveTokens(
      accessToken: result['access_token']!,
      refreshToken: result['refresh_token']!,
    );

    return getProfile();
  }

  Future<Map<String, String>> _launchMicrosoftAuth() async {
    // In a real implementation, this would use flutter_web_auth_2
    // to open a WebView to the Django OAuth URL
    throw UnimplementedError(
      'Microsoft OAuth WebView flow - implement with flutter_web_auth_2',
    );
  }

  Future<User> getProfile() async {
    final resp = await _api.get(ApiPaths.me);
    return User.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  Future<void> signOut() async {
    await _storage.clearTokens();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
  }

  Future<bool> isAuthenticated() => _storage.hasTokens();
}
