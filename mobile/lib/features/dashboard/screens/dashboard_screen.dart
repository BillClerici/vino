import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../help/help_launcher.dart';

import '../../../core/models/place.dart';
import '../../../core/models/visit.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/rating_stars.dart';
import '../providers/dashboard_provider.dart';

/// Shared scroll behavior that enables mouse/trackpad drag for carousels.
final _carouselScrollBehavior = const MaterialScrollBehavior().copyWith(
  dragDevices: {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  },
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Trip Me'),
        actions: [helpButton(context, routePrefix: '/dashboard')],
      ),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatsRow(stats: data.stats),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Active Trips',
                onViewAll: () => context.go('/trips'),
              ),
              if (data.activeTrips.isNotEmpty)
                _TripCarousel(trips: data.activeTrips)
              else
                const EmptyState(icon: Icons.map, title: 'No active trips'),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Recent Visits',
                onViewAll: () => context.go('/visits'),
              ),
              if (data.recentVisits.isNotEmpty)
                _VisitCarousel(visits: data.recentVisits)
              else
                const EmptyState(icon: Icons.place, title: 'No visits yet'),
              const SizedBox(height: 24),
              if (data.discover.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Discover',
                  onViewAll: () => context.go('/explore'),
                ),
                _DiscoverCarousel(places: data.discover),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Active Trips Carousel ───────────────────────────────────────

class _TripCarousel extends StatefulWidget {
  final List<DashboardTrip> trips;
  const _TripCarousel({required this.trips});

  @override
  State<_TripCarousel> createState() => _TripCarouselState();
}

class _TripCarouselState extends State<_TripCarousel> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ScrollConfiguration(
        behavior: _carouselScrollBehavior,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: widget.trips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final trip = widget.trips[index];
            return SizedBox(
              width: MediaQuery.of(context).size.width * 0.82,
              child: _TripCard(trip: trip),
            );
          },
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final DashboardTrip trip;
  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => context.push('/trips/${trip.id}'),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (trip.coverImage.isNotEmpty)
              Image.network(trip.coverImage,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _gradientBg(colorScheme.primary))
            else
              _gradientBg(colorScheme.primary),
            _darkOverlay(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: _StatusChip(status: trip.status),
                  ),
                  const Spacer(),
                  Text(trip.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (trip.stopNames.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(trip.stopNames.join(' → '),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  _MetaRow(trip: trip),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final DashboardTrip trip;
  const _MetaRow({required this.trip});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        color: Colors.white.withValues(alpha: 0.8), fontSize: 12);
    final iconColor = Colors.white.withValues(alpha: 0.8);

    return Row(
      children: [
        Icon(Icons.location_on, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text('${trip.stopCount} stops', style: style),
        const SizedBox(width: 16),
        Icon(Icons.people, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text('${trip.memberCount} members', style: style),
        if (trip.scheduledDate != null) ...[
          const SizedBox(width: 16),
          Icon(Icons.calendar_today, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(trip.scheduledDate!, style: style),
        ],
      ],
    );
  }
}

// ── Recent Visits Carousel ──────────────────────────────────────

class _VisitCarousel extends StatefulWidget {
  final List<VisitLog> visits;
  const _VisitCarousel({required this.visits});

  @override
  State<_VisitCarousel> createState() => _VisitCarouselState();
}

class _VisitCarouselState extends State<_VisitCarousel> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ScrollConfiguration(
        behavior: _carouselScrollBehavior,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: widget.visits.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final visit = widget.visits[index];
            return SizedBox(
              width: MediaQuery.of(context).size.width * 0.82,
              child: _VisitCard(visit: visit),
            );
          },
        ),
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  final VisitLog visit;
  const _VisitCard({required this.visit});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = visit.place?.imageUrl ?? '';

    return GestureDetector(
      onTap: () => context.push('/visits/${visit.id}'),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              Image.network(imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _gradientBg(colorScheme.primary))
            else
              _gradientBg(colorScheme.primary),
            _darkOverlay(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rating in top right
                  if (visit.ratingOverall != null)
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: RatingStars(
                            rating: visit.ratingOverall, size: 14),
                      ),
                    ),
                  const Spacer(),
                  Text(visit.place?.name ?? 'Unknown',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      Text(visit.visitedAt.substring(0, 10),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12)),
                      if (visit.place?.location.isNotEmpty == true) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.place,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(visit.place!.location,
                              style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      if (visit.winesCount > 0) ...[
                        const SizedBox(width: 16),
                        Icon(Icons.local_drink,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        Text('${visit.winesCount} wines',
                            style: TextStyle(
                                color:
                                    Colors.white.withValues(alpha: 0.8),
                                fontSize: 12)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Discover Carousel ───────────────────────────────────────────

class _DiscoverCarousel extends StatefulWidget {
  final List<Place> places;
  const _DiscoverCarousel({required this.places});

  @override
  State<_DiscoverCarousel> createState() => _DiscoverCarouselState();
}

class _DiscoverCarouselState extends State<_DiscoverCarousel> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ScrollConfiguration(
        behavior: _carouselScrollBehavior,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: widget.places.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final place = widget.places[index];
            return SizedBox(
              width: MediaQuery.of(context).size.width * 0.82,
              child: _DiscoverCard(place: place),
            );
          },
        ),
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  final Place place;
  const _DiscoverCard({required this.place});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => context.push('/explore/${place.id}'),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (place.imageUrl.isNotEmpty)
              Image.network(place.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _gradientBg(colorScheme.primary))
            else
              _gradientBg(colorScheme.primary),
            _darkOverlay(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Place type chip
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        place.placeType.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(place.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (place.location.isNotEmpty) ...[
                        Icon(Icons.place,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(place.location,
                              style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      if (place.avgRating != null) ...[
                        const SizedBox(width: 16),
                        RatingStars(
                            rating: place.avgRating!.round(), size: 12),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared Widgets ──────────────────────────────────────────────

Widget _gradientBg(Color primary) {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          primary,
          primary.withValues(alpha: 0.7),
          const Color(0xFF5DADE2),
        ],
      ),
    ),
  );
}

Widget _darkOverlay() {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.1),
          Colors.black.withValues(alpha: 0.7),
        ],
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color get _color {
    switch (status) {
      case 'draft':
        return Colors.grey[700]!;
      case 'planning':
        return Colors.blue[700]!;
      case 'confirmed':
        return Colors.green[700]!;
      case 'in_progress':
        return Colors.orange[700]!;
      default:
        return Colors.grey[700]!;
    }
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int current;
  const _PageDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: current == i ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: current == i
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(label: 'Trips', value: '${stats['trip_count'] ?? 0}', color: Colors.blue),
        _StatCard(label: 'Visits', value: '${stats['visit_count'] ?? 0}', color: Colors.teal),
        _StatCard(label: 'Places', value: '${stats['unique_places'] ?? 0}', color: Colors.deepPurple),
        _StatCard(
          label: 'Avg Rating',
          value: (stats['avg_rating'] as num?)?.toStringAsFixed(1) ?? '-',
          color: Colors.amber,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Text(value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      )),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onViewAll;
  const _SectionHeader({required this.title, this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (onViewAll != null)
          TextButton(onPressed: onViewAll, child: const Text('View All')),
      ],
    );
  }
}
