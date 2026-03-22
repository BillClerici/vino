import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';
import '../../config/constants.dart';
import '../../config/env.dart';

/// Attaches JWT token to requests and handles 401 refresh.
/// Uses QueuedInterceptor so async token reads complete before the request fires.
class AuthInterceptor extends QueuedInterceptor {
  final Dio _dio;
  final SecureStorageService _storage;
  final void Function()? onAuthExpired;
  bool _isRefreshing = false;

  AuthInterceptor(this._dio, this._storage, {this.onAuthExpired});

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await _storage.getRefreshToken();
        if (refreshToken == null) {
          _isRefreshing = false;
          return handler.reject(err);
        }

        final refreshDio = Dio(BaseOptions(baseUrl: EnvConfig.apiBaseUrl));
        final resp = await refreshDio.post(
          ApiPaths.tokenRefresh,
          data: {'refresh': refreshToken},
        );

        final newAccess = resp.data['access'] as String;
        final newRefresh = resp.data['refresh'] as String?;

        await _storage.saveTokens(
          accessToken: newAccess,
          refreshToken: newRefresh ?? refreshToken,
        );

        // Retry original request
        final options = err.requestOptions;
        options.headers['Authorization'] = 'Bearer $newAccess';
        final retryResp = await _dio.fetch(options);
        _isRefreshing = false;
        return handler.resolve(retryResp);
      } catch (_) {
        _isRefreshing = false;
        await _storage.clearTokens();
        onAuthExpired?.call();
      }
    }
    handler.next(err);
  }
}

/// Catches 403 subscription-required errors.
class SubscriptionInterceptor extends Interceptor {
  final void Function()? onSubscriptionRequired;

  SubscriptionInterceptor({this.onSubscriptionRequired});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 403) {
      final data = err.response?.data;
      if (data is Map &&
          data['detail']?.toString().contains('subscription') == true) {
        onSubscriptionRequired?.call();
      }
    }
    handler.next(err);
  }
}

/// Unwraps the Vino API envelope and throws typed exceptions.
class EnvelopeInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Let non-JSON responses through as-is
    if (response.data is! Map<String, dynamic>) {
      handler.next(response);
      return;
    }

    final envelope = response.data as Map<String, dynamic>;
    final success = envelope['success'] as bool? ?? true;

    if (!success) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: (envelope['errors'] ?? 'Request failed').toString(),
        ),
      );
      return;
    }

    // Keep the full envelope — let callers access data and meta
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }
}
