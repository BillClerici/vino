import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/trip.dart';
import '../../help/help_launcher.dart';
import '../providers/trips_provider.dart';

class LiveTripScreen extends ConsumerStatefulWidget {
  final String tripId;
  const LiveTripScreen({super.key, required this.tripId});

  @override
  ConsumerState<LiveTripScreen> createState() => _LiveTripScreenState();
}

class _LiveTripScreenState extends ConsumerState<LiveTripScreen> {
  int _currentStopIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripDetailProvider(widget.tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Trip'),
        actions: [helpButton(context, routePrefix: '/trips')],
      ),
      body: tripState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (trip) {
          final stops = trip.tripStops ?? [];
          if (stops.isEmpty) {
            return const Center(child: Text('No stops in this trip'));
          }
          final currentStop =
              _currentStopIndex < stops.length ? stops[_currentStopIndex] : null;

          return Column(
            children: [
              // Progress bar
              LinearProgressIndicator(
                value: stops.isNotEmpty
                    ? (_currentStopIndex + 1) / stops.length
                    : 0,
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Stop ${_currentStopIndex + 1} of ${stops.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              // Current stop card
              if (currentStop != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.place,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 16),
                            Text(
                              currentStop.place?.name ?? 'Unknown',
                              style: Theme.of(context).textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            if (currentStop.place?.location.isNotEmpty ==
                                true) ...[
                              const SizedBox(height: 8),
                              Text(currentStop.place!.location),
                            ],
                            const SizedBox(height: 32),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _ActionButton(
                                  icon: Icons.check_circle,
                                  label: 'Check In',
                                  onPressed: () =>
                                      _checkIn(currentStop),
                                ),
                                _ActionButton(
                                  icon: Icons.place,
                                  label: 'Add Wine',
                                  onPressed: () {},
                                ),
                                _ActionButton(
                                  icon: Icons.star,
                                  label: 'Rate',
                                  onPressed: () {},
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Navigation buttons
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (_currentStopIndex > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                setState(() => _currentStopIndex--),
                            child: const Text('Previous'),
                          ),
                        ),
                      if (_currentStopIndex > 0) const SizedBox(width: 16),
                      Expanded(
                        child: _currentStopIndex < stops.length - 1
                            ? FilledButton(
                                onPressed: () =>
                                    setState(() => _currentStopIndex++),
                                child: const Text('Next Stop'),
                              )
                            : FilledButton(
                                onPressed: () =>
                                    _completeTrip(context, ref),
                                child: const Text('Complete Trip'),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _checkIn(TripStop stop) async {
    final api = ref.read(apiClientProvider);
    try {
      await api.post(
          '${ApiPaths.trips}${widget.tripId}/live/checkin/${stop.id}/');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Checked in at ${stop.place?.name ?? ''}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _completeTrip(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiClientProvider);
    await api.post('${ApiPaths.trips}${widget.tripId}/complete/');
    if (context.mounted) {
      context.go('/trips');
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 28,
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
