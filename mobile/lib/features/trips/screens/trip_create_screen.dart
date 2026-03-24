import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/trip_service.dart';

class TripCreateScreen extends ConsumerStatefulWidget {
  const TripCreateScreen({super.key});

  @override
  ConsumerState<TripCreateScreen> createState() => _TripCreateScreenState();
}

class _TripCreateScreenState extends ConsumerState<TripCreateScreen> {
  bool _sheetShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sheetShown) {
      _sheetShown = true;
      // Show the bottom sheet after the frame renders
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSheet());
    }
  }

  Future<void> _showSheet() async {
    final input = await showStartTripSheet(context);

    if (!mounted) return;

    if (input == null) {
      // User cancelled — go back to trips list
      context.pop();
      return;
    }

    // Create the trip
    try {
      final api = ref.read(apiClientProvider);
      final tripResp = await api.post(ApiPaths.trips, data: {
        'name': input.tripName,
        'status': 'draft',
        'scheduled_date': input.scheduledDate,
        'end_date': input.endDate,
        'meeting_time': input.meetingTime,
      });
      if (mounted) {
        final tripId =
            (tripResp.data['data'] as Map<String, dynamic>)['id'] as String;
        context.go('/trips/$tripId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Transparent scaffold — the bottom sheet is the UI
    return Scaffold(
      appBar: AppBar(title: const Text('Plan a Trip')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
