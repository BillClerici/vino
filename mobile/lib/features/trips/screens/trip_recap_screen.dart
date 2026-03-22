import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/rating_stars.dart';

final tripRecapProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, tripId) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiPaths.tripRecap(tripId));
  return resp.data['data'] as Map<String, dynamic>;
});

class TripRecapScreen extends ConsumerWidget {
  final String tripId;
  const TripRecapScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recapState = ref.watch(tripRecapProvider(tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Recap'),
        actions: [
          recapState.whenOrNull(
                data: (data) => IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () => _share(data),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: recapState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) => _RecapBody(data: data),
      ),
    );
  }

  void _share(Map<String, dynamic> data) {
    final trip = data['trip'] as Map<String, dynamic>;
    final stats = data['stats'] as Map<String, dynamic>;
    final stops = data['stops'] as List;

    final buffer = StringBuffer();
    buffer.writeln('${trip['name']} - Trip Recap');
    buffer.writeln('');
    if (trip['scheduled_date'] != null) {
      buffer.writeln('Date: ${trip['scheduled_date']}');
    }
    buffer.writeln(
      '${stats['stops_visited']} stops | '
      '${stats['total_wines']} wines | '
      '${stats['total_travel_miles']} miles',
    );
    buffer.writeln('');
    for (final stop in stops) {
      final place = stop['place'] as Map<String, dynamic>;
      final wines = stop['wines_tasted'] as List;
      buffer.writeln('${place['name']} (${place['city']})');
      for (final w in wines) {
        final rating = w['rating'] != null ? ' ${w['rating']}/5' : '';
        final fav = w['is_favorite'] == true ? ' [fav]' : '';
        buffer.writeln('  - ${w['name']}$rating$fav');
      }
    }
    buffer.writeln('');
    buffer.writeln('Shared from Vino');

    Share.share(buffer.toString());
  }
}

class _RecapBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RecapBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final trip = data['trip'] as Map<String, dynamic>;
    final stats = data['stats'] as Map<String, dynamic>;
    final stops = data['stops'] as List;
    final members = data['members'] as List;
    final photos = data['photos'] as List;
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Trip header
        Text(
          trip['name'] as String? ?? 'Trip',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (trip['description'] != null &&
            (trip['description'] as String).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(trip['description'] as String,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
        if (trip['scheduled_date'] != null) ...[
          const SizedBox(height: 4),
          Text(
            trip['scheduled_date'] as String,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
        ],
        const SizedBox(height: 16),

        // Stats row
        Card(
          color: colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatBadge(
                    '${stats['stops_visited']}', 'Stops', Icons.place),
                _StatBadge(
                    '${stats['total_wines']}', 'Wines', Icons.wine_bar),
                _StatBadge(
                    '${stats['total_travel_miles']}', 'Miles', Icons.route),
                _StatBadge(
                    '${stats['total_members']}', 'Members', Icons.people),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Photos gallery
        if (photos.isNotEmpty) ...[
          Text('Photos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  photos[i] as String,
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 120,
                    height: 120,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Stop-by-stop recap
        Text('Your Journey', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ...stops.asMap().entries.map((entry) {
          final i = entry.key;
          final stop = entry.value as Map<String, dynamic>;
          return _StopRecapCard(stop: stop, index: i, isLast: i == stops.length - 1);
        }),

        // Members
        if (members.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Trip Crew', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: members.map((m) {
              final name = m['display_name'] as String? ?? '?';
              return Chip(
                avatar: CircleAvatar(
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                ),
                label: Text(name),
              );
            }).toList(),
          ),
        ],

        const SizedBox(height: 32),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  const _StatBadge(this.value, this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _StopRecapCard extends StatelessWidget {
  final Map<String, dynamic> stop;
  final int index;
  final bool isLast;
  const _StopRecapCard({
    required this.stop,
    required this.index,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final place = stop['place'] as Map<String, dynamic>;
    final wines = stop['wines_tasted'] as List;
    final ratings = stop['avg_ratings'] as Map<String, dynamic>? ?? {};
    final checkedIn = stop['checked_in'] as bool? ?? false;
    final travelMiles = stop['travel_miles'];
    final colorScheme = Theme.of(context).colorScheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: checkedIn ? colorScheme.primary : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: checkedIn
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '${index + 1}',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey[300],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Content
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Place header
                    Row(
                      children: [
                        if ((place['image_url'] as String?)?.isNotEmpty == true)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              place['image_url'] as String,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        if ((place['image_url'] as String?)?.isNotEmpty == true)
                          const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(place['name'] as String? ?? '',
                                  style: Theme.of(context).textTheme.titleSmall),
                              if ((place['city'] as String?)?.isNotEmpty == true)
                                Text(
                                  '${place['city']}, ${place['state'] ?? ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Ratings
                    if (ratings.isNotEmpty && ratings['avg_overall'] != null) ...[
                      const SizedBox(height: 8),
                      RatingStars(
                        rating: (ratings['avg_overall'] as num?)?.round(),
                        size: 18,
                      ),
                    ],

                    // Travel info
                    if (travelMiles != null && travelMiles > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${stop['travel_minutes'] ?? '?'} min drive ($travelMiles mi)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    ],

                    // Wines
                    if (wines.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...wines.map((w) {
                        final wineMap = w as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.wine_bar,
                                  size: 14, color: colorScheme.secondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  wineMap['name'] as String? ?? '',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              if (wineMap['rating'] != null)
                                Text(
                                  '${wineMap['rating']}/5',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (wineMap['is_favorite'] == true)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child:
                                      Icon(Icons.favorite, size: 12, color: Colors.red),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],

                    if (!checkedIn) ...[
                      const SizedBox(height: 8),
                      Text('Skipped',
                          style: TextStyle(
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                              fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
