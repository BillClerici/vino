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

  /// Scan wine/beer label with AI vision: POST /api/v1/scan-label/
  static const scanLabel = '/api/v1/scan-label/';

  /// AI palate analysis: POST /api/v1/palate/analyze/
  static const palateAnalyze = '/api/v1/palate/analyze/';

  /// AI sommelier chat: POST /api/v1/palate/chat/
  static const palateChat = '/api/v1/palate/chat/';

  /// Trip recap: GET /api/v1/trips/{tripId}/recap/
  static String tripRecap(String tripId) => '/api/v1/trips/$tripId/recap/';

  /// Group palate match: POST /api/v1/trips/{tripId}/palate-match/
  static String palateMatch(String tripId) =>
      '/api/v1/trips/$tripId/palate-match/';

  /// Live trip activity feed: GET /api/v1/trips/{tripId}/activity/
  static String tripActivity(String tripId) =>
      '/api/v1/trips/$tripId/activity/';

  /// Ask Sippy (trip-aware AI chat): POST /api/v1/trips/{tripId}/chat/
  static String tripChat(String tripId) => '/api/v1/trips/$tripId/chat/';

  /// Sippy trip planner (LangGraph): POST /api/v1/trips/plan/
  static const tripPlan = '/api/v1/trips/plan/';

  /// Sippy conversations
  static const conversations = '/api/v1/conversations/';
  static String conversationDetail(String id) => '/api/v1/conversations/$id/';
  static String conversationRetry(String id) =>
      '/api/v1/conversations/$id/retry/';
}

class StorageKeys {
  static const accessToken = 'vino_access_token';
  static const refreshToken = 'vino_refresh_token';
}
