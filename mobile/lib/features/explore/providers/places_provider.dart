import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';
import '../../../core/models/place.dart';

final placesProvider =
    AsyncNotifierProvider<PlacesNotifier, PaginatedResponse<Place>>(
        () => PlacesNotifier());

class PlacesNotifier extends AsyncNotifier<PaginatedResponse<Place>> {
  String _query = '';
  String? _placeType;

  @override
  Future<PaginatedResponse<Place>> build() => _fetch();

  Future<PaginatedResponse<Place>> _fetch({int page = 1}) async {
    final api = ref.read(apiClientProvider);
    final params = <String, dynamic>{'page': page};
    if (_query.isNotEmpty) params['q'] = _query;
    if (_placeType != null) params['place_type'] = _placeType;

    final resp = await api.get(ApiPaths.places, queryParameters: params);
    return PaginatedResponse.fromJson(
      resp.data as Map<String, dynamic>,
      (json) => Place.fromJson(json),
    );
  }

  Future<void> search(String query) async {
    _query = query;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<void> filterByType(String? type) async {
    _placeType = type;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    final next = await _fetch(page: current.page + 1);
    state = AsyncValue.data(PaginatedResponse(
      items: [...current.items, ...next.items],
      page: next.page,
      pageSize: next.pageSize,
      total: next.total,
    ));
  }

  Future<void> toggleFavorite(String placeId) async {
    final api = ref.read(apiClientProvider);
    await api.post('${ApiPaths.places}$placeId/favorite/');
    ref.invalidateSelf();
  }
}

final favoritesProvider = FutureProvider<List<Place>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('${ApiPaths.places}favorites/',
      queryParameters: {'page_size': '50'});
  final data = resp.data['data'] as List<dynamic>;
  return data
      .map((e) => Place.fromJson(
          (e as Map<String, dynamic>)['place'] as Map<String, dynamic>))
      .toList();
});

final placeDetailProvider =
    FutureProvider.family<Place, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('${ApiPaths.places}$id/');
  return Place.fromJson(resp.data['data'] as Map<String, dynamic>);
});

final placeMapProvider = FutureProvider<List<Place>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('${ApiPaths.places}map/');
  return (resp.data['data'] as List)
      .map((e) => Place.fromJson(e as Map<String, dynamic>))
      .toList();
});
