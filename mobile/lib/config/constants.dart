class ApiPaths {
  static const auth = '/api/v1/auth/mobile';
  static const tokenRefresh = '/api/auth/token/refresh/';
  static const me = '/api/v1/me/';
  static const meStats = '/api/v1/me/stats/';
  static const dashboard = '/api/v1/dashboard/';
  static const places = '/api/v1/places/';
  static const visits = '/api/v1/visits/';
  static const trips = '/api/v1/trips/';
  static const palate = '/api/v1/palate/';
  static const lookups = '/api/v1/lookups/';
  static const subscriptionStatus = '/api/v1/subscription/status/';
  static const subscriptionCheckout = '/api/v1/subscription/checkout/';
  static const subscriptionPortal = '/api/v1/subscription/portal/';
  static const config = '/api/v1/config/';

  /// Upload drink photo: POST /api/v1/visits/{visitId}/wines/{wineId}/photo/
  static String winePhoto(String visitId, String wineId) =>
      '/api/v1/visits/$visitId/wines/$wineId/photo/';
}

class StorageKeys {
  static const accessToken = 'vino_access_token';
  static const refreshToken = 'vino_refresh_token';
}
