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

  /// Nearby places search
  static const nearbyPlaces = '/api/v1/places/nearby/';

  /// History map: all visited places with stats
  static const historyMap = '/api/v1/visits/history-map/';

  /// Badges
  static const badges = '/api/v1/badges/';

  /// Cellar / Purchase Dashboard
  static const cellar = '/api/v1/cellar/';

  /// Wine & Food Pairings: POST /api/v1/places/{placeId}/pairings/
  static String placePairings(String placeId) =>
      '/api/v1/places/$placeId/pairings/';

  /// Smart recommendations for a place: POST /api/v1/places/{placeId}/recommend/
  static String placeRecommend(String placeId) =>
      '/api/v1/places/$placeId/recommend/';

  /// Tasting flight for a place: POST /api/v1/places/{placeId}/flight/
  static String placeFlight(String placeId) =>
      '/api/v1/places/$placeId/flight/';

  /// Save AI results (flight, recommendations, pairings) to visit metadata
  static String liveMetadata(String tripId, String visitId) =>
      '/api/v1/trips/$tripId/live/metadata/$visitId/';

  /// Wine wishlist
  static const wishlist = '/api/v1/wishlist/';
  static String wishlistDetail(String id) => '/api/v1/wishlist/$id/';
  static String wishlistCheck(String placeId) =>
      '/api/v1/wishlist/check/$placeId/';

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
