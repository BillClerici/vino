import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/place.dart';
import '../../../core/models/visit.dart';

class DashboardTrip {
  final String id;
  final String name;
  final String status;
  final String? scheduledDate;
  final String? endDate;
  final int memberCount;
  final int stopCount;
  final String? createdByName;
  final String coverImage;
  final List<String> stopNames;

  const DashboardTrip({
    required this.id,
    required this.name,
    this.status = 'draft',
    this.scheduledDate,
    this.endDate,
    this.memberCount = 0,
    this.stopCount = 0,
    this.createdByName,
    this.coverImage = '',
    this.stopNames = const [],
  });

  /// True if trip should open in live mode (in progress, or confirmed and scheduled today/earlier).
  bool get isLive {
    if (status == 'in_progress') return true;
    if (status == 'confirmed' && scheduledDate != null) {
      final scheduled = DateTime.tryParse(scheduledDate!);
      if (scheduled != null) {
        final today = DateTime.now();
        return !scheduled.isAfter(DateTime(today.year, today.month, today.day));
      }
    }
    return false;
  }

  factory DashboardTrip.fromJson(Map<String, dynamic> json) {
    return DashboardTrip(
      id: json['id'] as String,
      name: json['name'] as String,
      status: json['status'] as String? ?? 'draft',
      scheduledDate: json['scheduled_date'] as String?,
      endDate: json['end_date'] as String?,
      memberCount: json['member_count'] as int? ?? 0,
      stopCount: json['stop_count'] as int? ?? 0,
      createdByName: json['created_by_name'] as String?,
      coverImage: json['cover_image'] as String? ?? '',
      stopNames: (json['stop_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

class DashboardData {
  final Map<String, dynamic> stats;
  final List<VisitLog> recentVisits;
  final List<DashboardTrip> activeTrips;
  final List<Map<String, dynamic>> topPlaces;
  final List<Place> discover;

  DashboardData({
    required this.stats,
    required this.recentVisits,
    required this.activeTrips,
    required this.topPlaces,
    required this.discover,
  });
}

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  // Wait for auth — don't fetch if not logged in
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) throw Exception('Not authenticated');

  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiPaths.dashboard);
  final data = resp.data['data'] as Map<String, dynamic>;

  return DashboardData(
    stats: data['stats'] as Map<String, dynamic>,
    recentVisits: (data['recent_visits'] as List)
        .map((e) => VisitLog.fromJson(e as Map<String, dynamic>))
        .toList(),
    activeTrips: (data['active_trips'] as List)
        .map((e) => DashboardTrip.fromJson(e as Map<String, dynamic>))
        .toList(),
    topPlaces: (data['top_places'] as List)
        .map((e) => e as Map<String, dynamic>)
        .toList(),
    discover: (data['discover'] as List)
        .map((e) => Place.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
});
