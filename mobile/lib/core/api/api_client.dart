import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/env.dart';
import '../auth/auth_provider.dart';
import '../storage/secure_storage.dart';
import 'api_interceptors.dart';

/// Single shared storage instance used by both ApiClient and AuthService.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.read(secureStorageProvider);
  return ApiClient(storage, onAuthExpired: () {
    // Clear auth state so the router redirects to login
    ref.read(authStateProvider.notifier).signOut();
  });
});

class ApiClient {
  late final Dio dio;

  ApiClient(SecureStorageService storage, {void Function()? onAuthExpired}) {
    dio = Dio(BaseOptions(
      baseUrl: EnvConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 90),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.addAll([
      AuthInterceptor(dio, storage, onAuthExpired: onAuthExpired),
      SubscriptionInterceptor(),
      EnvelopeInterceptor(),
    ]);
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) =>
      dio.get(path, queryParameters: queryParameters);

  Future<Response> post(String path, {dynamic data}) =>
      dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      dio.put(path, data: data);

  Future<Response> patch(String path, {dynamic data}) =>
      dio.patch(path, data: data);

  Future<Response> delete(String path) => dio.delete(path);
}
