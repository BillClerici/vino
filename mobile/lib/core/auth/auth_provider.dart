import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/user.dart';
import 'auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final api = ref.read(apiClientProvider);
  final storage = ref.read(secureStorageProvider);
  return AuthService(api, storage);
});

final authStateProvider =
    AsyncNotifierProvider<AuthNotifier, User?>(() => AuthNotifier());

class AuthNotifier extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    try {
      final service = ref.read(authServiceProvider);
      final isLoggedIn = await service.isAuthenticated();
      if (!isLoggedIn) return null;
      return await service.getProfile();
    } catch (e) {
      debugPrint('[AuthNotifier.build] error: $e');
      return null;
    }
  }

  Future<void> devLogin({String? email}) async {
    state = const AsyncValue.loading();
    try {
      final service = ref.read(authServiceProvider);
      final user = await service.devLogin(email: email);
      debugPrint('[AuthNotifier.devLogin] success: ${user.email}');
      state = AsyncValue.data(user);
    } catch (e, st) {
      debugPrint('[AuthNotifier.devLogin] FAILED: $e');
      debugPrint('[AuthNotifier.devLogin] stackTrace: $st');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(authServiceProvider);
      return await service.signInWithGoogle();
    });
  }

  Future<void> signInWithMicrosoft() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(authServiceProvider);
      return await service.signInWithMicrosoft();
    });
  }

  Future<void> signOut() async {
    try {
      final service = ref.read(authServiceProvider);
      await service.signOut();
    } catch (_) {}
    state = const AsyncValue.data(null);
  }

  Future<void> refreshProfile() async {
    final service = ref.read(authServiceProvider);
    try {
      final user = await service.getProfile();
      state = AsyncValue.data(user);
    } catch (_) {}
  }
}
