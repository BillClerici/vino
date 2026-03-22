import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/constants.dart';
import '../api/api_client.dart';

/// Creates a new trip from a place and navigates to the trip detail.
/// Used by Explore list, Favorites, Map, and Place Detail screens.
Future<void> startTripFromPlace({
  required BuildContext context,
  required WidgetRef ref,
  required String placeId,
  required String placeName,
}) async {
  final api = ref.read(apiClientProvider);
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

  try {
    // Create the trip
    final tripResp = await api.post(ApiPaths.trips, data: {
      'name': 'Trip to $placeName',
      'status': 'draft',
      'scheduled_date': today,
      'end_date': today,
      'meeting_time': '12:00',
    });
    final tripData = tripResp.data['data'] as Map<String, dynamic>;
    final tripId = tripData['id'] as String;

    // Add the place as the first stop
    await api.post('${ApiPaths.trips}$tripId/stops/', data: {
      'place': placeId,
      'duration_minutes': 60,
    });

    if (context.mounted) {
      context.go('/trips/$tripId');
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error creating trip: $e')));
    }
  }
}

/// Same as above but for Google Places data (not yet in our DB).
Future<void> startTripFromGooglePlace({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> place,
  required String placeType,
}) async {
  final api = ref.read(apiClientProvider);

  try {
    // Create place in DB first
    var name = (place['name'] as String? ?? '').trim();
    if (name.isEmpty) name = 'Unknown Place';
    final address = (place['address'] as String? ?? '').trim();
    var website = (place['website'] as String? ?? '').trim();
    if (website.isNotEmpty && !website.startsWith('http')) {
      website = 'https://$website';
    }

    final placeData = <String, dynamic>{
      'name': name,
      'place_type': placeType,
      'address': address,
      'city': (place['city'] as String? ?? '').trim(),
      'state': (place['state'] as String? ?? '').trim(),
      'website': website,
      'phone': (place['phone'] as String? ?? '').trim(),
    };
    final lat = place['latitude'];
    final lng = place['longitude'];
    if (lat != null) {
      final v = lat is double ? lat : double.tryParse('$lat');
      if (v != null) placeData['latitude'] = double.parse(v.toStringAsFixed(6));
    }
    if (lng != null) {
      final v = lng is double ? lng : double.tryParse('$lng');
      if (v != null) placeData['longitude'] = double.parse(v.toStringAsFixed(6));
    }

    final placeResp = await api.post(ApiPaths.places, data: placeData);
    final placeId =
        (placeResp.data['data'] as Map<String, dynamic>)['id'] as String;

    if (context.mounted) {
      await startTripFromPlace(
        context: context,
        ref: ref,
        placeId: placeId,
        placeName: name,
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
