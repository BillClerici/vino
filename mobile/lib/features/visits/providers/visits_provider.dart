import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';
import '../../../core/models/visit.dart';

final visitsProvider =
    AsyncNotifierProvider<VisitsNotifier, PaginatedResponse<VisitLog>>(
        () => VisitsNotifier());

class VisitsNotifier extends AsyncNotifier<PaginatedResponse<VisitLog>> {
  String _query = '';
  int? _ratingMin;

  @override
  Future<PaginatedResponse<VisitLog>> build() => _fetch();

  Future<PaginatedResponse<VisitLog>> _fetch({int page = 1}) async {
    final api = ref.read(apiClientProvider);
    final params = <String, dynamic>{'page': page};
    if (_query.isNotEmpty) params['q'] = _query;
    if (_ratingMin != null) params['rating_min'] = _ratingMin;

    final resp = await api.get(ApiPaths.visits, queryParameters: params);
    return PaginatedResponse.fromJson(
      resp.data as Map<String, dynamic>,
      (json) => VisitLog.fromJson(json),
    );
  }

  Future<void> search(String query) async {
    _query = query;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<void> filterByRating(int? min) async {
    _ratingMin = min;
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
}

final visitDetailProvider =
    FutureProvider.family<VisitLog, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('${ApiPaths.visits}$id/');
  return VisitLog.fromJson(resp.data['data'] as Map<String, dynamic>);
});
