import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_response.dart';
import '../../../core/models/trip.dart';

final tripsProvider =
    AutoDisposeAsyncNotifierProvider<TripsNotifier, PaginatedResponse<Trip>>(
        () => TripsNotifier());

class TripsNotifier
    extends AutoDisposeAsyncNotifier<PaginatedResponse<Trip>> {
  String _query = '';
  String? _status;

  @override
  Future<PaginatedResponse<Trip>> build() => _fetch();

  Future<PaginatedResponse<Trip>> _fetch({int page = 1}) async {
    final api = ref.read(apiClientProvider);
    final params = <String, dynamic>{'page': page};
    if (_query.isNotEmpty) params['q'] = _query;
    if (_status != null) params['status'] = _status;

    final resp = await api.get(ApiPaths.trips, queryParameters: params);
    return PaginatedResponse.fromJson(
      resp.data as Map<String, dynamic>,
      (json) => Trip.fromJson(json),
    );
  }

  Future<void> search(String query) async {
    _query = query;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<void> filterByStatus(String? status) async {
    _status = status;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }
}

final tripDetailProvider =
    FutureProvider.autoDispose.family<Trip, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get('${ApiPaths.trips}$id/');
  return Trip.fromJson(resp.data['data'] as Map<String, dynamic>);
});
