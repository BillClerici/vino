import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/env.dart';
import '../../../core/models/visit.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../../core/widgets/rating_stars.dart';
import '../../../core/widgets/search_bar.dart';
import '../../help/help_launcher.dart';
import '../providers/visits_provider.dart';

enum _SortOption {
  dateDesc('Newest First', '-visited_at'),
  dateAsc('Oldest First', 'visited_at'),
  ratingDesc('Highest Rated', '-rating_overall'),
  ratingAsc('Lowest Rated', 'rating_overall');

  final String label;
  final String ordering;
  const _SortOption(this.label, this.ordering);
}

class VisitsScreen extends ConsumerStatefulWidget {
  const VisitsScreen({super.key});

  @override
  ConsumerState<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends ConsumerState<VisitsScreen> {
  _SortOption _sort = _SortOption.dateDesc;
  bool _groupByPlace = false;

  void _changeSort(_SortOption option) {
    setState(() => _sort = option);
    ref.read(visitsProvider.notifier).setOrdering(option.ordering);
  }

  @override
  Widget build(BuildContext context) {
    final visitsState = ref.watch(visitsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('My Visits'),
        actions: [const NotificationBell(), helpButton(context, routePrefix: '/visits')],
      ),
      body: Column(
        children: [
          VinoSearchBar(
            hint: 'Search visits...',
            onChanged: (q) => ref.read(visitsProvider.notifier).search(q),
          ),

          // Sort & Group controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Sort dropdown
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<_SortOption>(
                        value: _sort,
                        isDense: true,
                        isExpanded: true,
                        icon: Icon(Icons.sort, size: 18, color: cs.outline),
                        style: Theme.of(context).textTheme.bodyMedium,
                        items: _SortOption.values
                            .map((o) => DropdownMenuItem(
                                  value: o,
                                  child: Text(o.label,
                                      style: const TextStyle(fontSize: 13)),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) _changeSort(v);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Group toggle
                FilterChip(
                  label: const Text('Group',
                      style: TextStyle(fontSize: 11)),
                  avatar: Icon(Icons.grid_view_rounded,
                      size: 14,
                      color: _groupByPlace ? cs.primary : cs.outline),
                  selected: _groupByPlace,
                  onSelected: (v) => setState(() => _groupByPlace = v),
                  selectedColor: cs.primaryContainer,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                ),
              ],
            ),
          ),

          Expanded(
            child: visitsState.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (paginated) {
                if (paginated.items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.wine_bar_rounded,
                    title: 'No visits yet',
                    subtitle:
                        'Start a trip and check in at a winery to begin your journey',
                  );
                }
                if (_groupByPlace) {
                  return _GroupedVisitList(visits: paginated.items);
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(visitsProvider.future),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                        left: 16, right: 16, top: 4, bottom: 16),
                    itemCount: paginated.items.length,
                    itemBuilder: (_, i) =>
                        _VisitCard(visit: paginated.items[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// VISIT CARD — hero image style
// ═══════════════════════════════════════════════════════════════════

class _VisitCard extends StatelessWidget {
  final VisitLog visit;
  const _VisitCard({required this.visit});

  String _resolveImage(String url) {
    if (url.isEmpty) return url;
    if (!kIsWeb) return url;
    if (url.contains('vinoshipper') || url.contains('s3.amazonaws')) {
      return '${EnvConfig.apiBaseUrl}/api/v1/image-proxy/?url=${Uri.encodeComponent(url)}';
    }
    return url;
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('EEE, MMM d, yyyy').format(dt);
    } catch (_) {
      return iso.substring(0, 10);
    }
  }

  String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inDays == 0) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
      if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';
      return '${(diff.inDays / 365).floor()}y ago';
    } catch (_) {
      return '';
    }
  }

  Color _ratingColor(int rating) {
    if (rating >= 5) return const Color(0xFF27AE60);
    if (rating >= 4) return const Color(0xFF2ECC71);
    if (rating >= 3) return const Color(0xFFF39C12);
    if (rating >= 2) return const Color(0xFFE67E22);
    return const Color(0xFFE74C3C);
  }

  IconData _placeIcon(String type) {
    switch (type) {
      case 'brewery':
        return Icons.sports_bar;
      case 'restaurant':
        return Icons.restaurant;
      default:
        return Icons.wine_bar_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final place = visit.place;
    final placeName = place?.name ?? 'Unknown Place';
    final placeType = place?.placeType ?? 'winery';
    final imageUrl = place?.imageUrl ?? '';
    final hasImage = imageUrl.isNotEmpty;
    final resolvedImage = hasImage ? _resolveImage(imageUrl) : '';
    final location = place?.location ?? '';
    final rating = visit.ratingOverall;
    final wineCount = visit.winesCount;
    final timeAgo = _timeAgo(visit.visitedAt);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => context.push('/visits/${visit.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero image / gradient header ──
            Stack(
              children: [
                SizedBox(
                  height: hasImage ? 130 : 80,
                  width: double.infinity,
                  child: hasImage
                      ? Image.network(
                          resolvedImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _gradientHeader(cs, placeType),
                        )
                      : _gradientHeader(cs, placeType),
                ),
                // Dark overlay
                if (hasImage)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.1),
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: const [0.2, 1.0],
                        ),
                      ),
                    ),
                  ),
                // Time ago badge top-left
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(timeAgo,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                // Place type badge top-right
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _placeTypeColor(placeType),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_placeIcon(placeType),
                            size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          placeType[0].toUpperCase() +
                              placeType.substring(1),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                // Rating badge bottom-right
                if (rating != null)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _ratingColor(rating),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 2),
                          Text('$rating',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                // Place name + location overlay
                Positioned(
                  left: 12,
                  right: 60,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        placeName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: hasImage
                              ? Colors.white
                              : cs.onPrimaryContainer,
                          shadows: hasImage
                              ? [
                                  Shadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                  )
                                ]
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (location.isNotEmpty)
                        Text(
                          location,
                          style: TextStyle(
                            fontSize: 12,
                            color: hasImage
                                ? Colors.white70
                                : cs.onPrimaryContainer
                                    .withValues(alpha: 0.7),
                            shadows: hasImage
                                ? [
                                    Shadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.5),
                                      blurRadius: 4,
                                    )
                                  ]
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Stats strip ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Date
                  Icon(Icons.calendar_today,
                      size: 13, color: cs.outline),
                  const SizedBox(width: 4),
                  Text(_formatDate(visit.visitedAt),
                      style: TextStyle(fontSize: 12, color: cs.outline)),
                  const Spacer(),
                  // Wine count
                  _statChip(
                    Icons.wine_bar,
                    '$wineCount',
                    cs.primary,
                    cs,
                  ),
                  if (rating != null) ...[
                    const SizedBox(width: 6),
                    RatingStars(rating: rating, size: 14),
                  ],
                  // Navigate arrow
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, size: 18, color: cs.outline),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientHeader(ColorScheme cs, String placeType) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer,
            _placeTypeColor(placeType).withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Center(
        child: Icon(_placeIcon(placeType),
            size: 36,
            color: cs.onPrimaryContainer.withValues(alpha: 0.3)),
      ),
    );
  }

  Widget _statChip(
      IconData icon, String value, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Color _placeTypeColor(String type) {
    switch (type) {
      case 'brewery':
        return const Color(0xFFE67E22);
      case 'restaurant':
        return const Color(0xFF27AE60);
      default:
        return const Color(0xFF8E44AD);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// GROUPED VIEW
// ═══════════════════════════════════════════════════════════════════

class _GroupedVisitList extends StatelessWidget {
  final List<VisitLog> visits;
  const _GroupedVisitList({required this.visits});

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<VisitLog>>{};
    final placeData = <String, VisitLog>{};
    for (final visit in visits) {
      final placeId = visit.place?.id ?? 'unknown';
      groups.putIfAbsent(placeId, () => []).add(visit);
      placeData.putIfAbsent(placeId, () => visit);
    }

    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => (placeData[a]?.place?.name ?? '')
          .compareTo(placeData[b]?.place?.name ?? ''));

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 16),
      itemCount: sortedKeys.length,
      itemBuilder: (context, i) {
        final placeId = sortedKeys[i];
        final placeVisits = groups[placeId]!;
        final representative = placeData[placeId]!;

        return _PlaceGroupCard(
          placeId: placeId,
          representative: representative,
          visits: placeVisits,
        );
      },
    );
  }
}

class _PlaceGroupCard extends StatelessWidget {
  final String placeId;
  final VisitLog representative;
  final List<VisitLog> visits;
  const _PlaceGroupCard({
    required this.placeId,
    required this.representative,
    required this.visits,
  });

  String _resolveImage(String url) {
    if (url.isEmpty) return url;
    if (!kIsWeb) return url;
    if (url.contains('vinoshipper') || url.contains('s3.amazonaws')) {
      return '${EnvConfig.apiBaseUrl}/api/v1/image-proxy/?url=${Uri.encodeComponent(url)}';
    }
    return url;
  }

  Color _placeTypeColor(String type) {
    switch (type) {
      case 'brewery':
        return const Color(0xFFE67E22);
      case 'restaurant':
        return const Color(0xFF27AE60);
      default:
        return const Color(0xFF8E44AD);
    }
  }

  IconData _placeIcon(String type) {
    switch (type) {
      case 'brewery':
        return Icons.sports_bar;
      case 'restaurant':
        return Icons.restaurant;
      default:
        return Icons.wine_bar_rounded;
    }
  }

  Color _ratingColor(int rating) {
    if (rating >= 5) return const Color(0xFF27AE60);
    if (rating >= 4) return const Color(0xFF2ECC71);
    if (rating >= 3) return const Color(0xFFF39C12);
    if (rating >= 2) return const Color(0xFFE67E22);
    return const Color(0xFFE74C3C);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final place = representative.place;
    final placeName = place?.name ?? 'Unknown Place';
    final placeType = place?.placeType ?? 'winery';
    final imageUrl = place?.imageUrl ?? '';
    final hasImage = imageUrl.isNotEmpty;
    final resolvedImage = hasImage ? _resolveImage(imageUrl) : '';
    final location = place?.location ?? '';

    // Aggregate stats
    final totalWines =
        visits.fold<int>(0, (sum, v) => sum + v.winesCount);
    final rated = visits.where((v) => v.ratingOverall != null).toList();
    final avgRating = rated.isNotEmpty
        ? (rated.fold<int>(0, (s, v) => s + v.ratingOverall!) /
                rated.length)
            .round()
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Place header with image ──
          GestureDetector(
            onTap: placeId != 'unknown'
                ? () => context.push('/explore/$placeId')
                : null,
            child: Stack(
              children: [
                SizedBox(
                  height: hasImage ? 110 : 70,
                  width: double.infinity,
                  child: hasImage
                      ? Image.network(resolvedImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _gradientHeader(cs, placeType))
                      : _gradientHeader(cs, placeType),
                ),
                if (hasImage)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.05),
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: const [0.2, 1.0],
                        ),
                      ),
                    ),
                  ),
                // Visit count badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      '${visits.length} ${visits.length == 1 ? 'visit' : 'visits'}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                // Avg rating badge
                if (avgRating != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _ratingColor(avgRating),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Colors.white, size: 13),
                          const SizedBox(width: 2),
                          Text('$avgRating avg',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                // Place name overlay
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        placeName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: hasImage
                              ? Colors.white
                              : cs.onPrimaryContainer,
                          shadows: hasImage
                              ? [
                                  Shadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                  )
                                ]
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (location.isNotEmpty)
                        Row(
                          children: [
                            Text(
                              location,
                              style: TextStyle(
                                fontSize: 12,
                                color: hasImage
                                    ? Colors.white70
                                    : cs.onPrimaryContainer
                                        .withValues(alpha: 0.7),
                                shadows: hasImage
                                    ? [
                                        Shadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.5),
                                          blurRadius: 4,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$totalWines tastings total',
                              style: TextStyle(
                                fontSize: 11,
                                color: hasImage
                                    ? Colors.white60
                                    : cs.onPrimaryContainer
                                        .withValues(alpha: 0.5),
                                shadows: hasImage
                                    ? [
                                        Shadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.5),
                                          blurRadius: 4,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Visit timeline rows ──
          ...visits.asMap().entries.map((entry) {
            final i = entry.key;
            final visit = entry.value;
            final isLast = i == visits.length - 1;
            return _VisitTimelineRow(
              visit: visit,
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _gradientHeader(ColorScheme cs, String placeType) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer,
            _placeTypeColor(placeType).withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Center(
        child: Icon(_placeIcon(placeType),
            size: 32,
            color: cs.onPrimaryContainer.withValues(alpha: 0.3)),
      ),
    );
  }
}

/// A single visit row in the grouped timeline view.
class _VisitTimelineRow extends StatelessWidget {
  final VisitLog visit;
  final bool isLast;
  const _VisitTimelineRow({required this.visit, required this.isLast});

  Color _ratingColor(int rating) {
    if (rating >= 5) return const Color(0xFF27AE60);
    if (rating >= 4) return const Color(0xFF2ECC71);
    if (rating >= 3) return const Color(0xFFF39C12);
    if (rating >= 2) return const Color(0xFFE67E22);
    return const Color(0xFFE74C3C);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rating = visit.ratingOverall;

    String dateLabel;
    String timeLabel = '';
    try {
      final dt = DateTime.parse(visit.visitedAt);
      dateLabel = DateFormat('MMM d, yyyy').format(dt);
      timeLabel = DateFormat('h:mm a').format(dt);
    } catch (_) {
      dateLabel = visit.visitedAt.substring(0, 10);
    }

    return InkWell(
      onTap: () => context.push('/visits/${visit.id}'),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Timeline dot + line
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: rating != null
                            ? _ratingColor(rating)
                            : cs.outline,
                        border: Border.all(
                          color: rating != null
                              ? _ratingColor(rating)
                                  .withValues(alpha: 0.3)
                              : cs.outlineVariant,
                          width: 2,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          color: cs.outlineVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Content
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: !isLast
                      ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                        )
                      : null,
                  child: Row(
                    children: [
                      // Date + wines
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dateLabel,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (timeLabel.isNotEmpty) ...[
                                  Text(timeLabel,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.outline)),
                                  Text(' · ',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.outline)),
                                ],
                                Text(
                                  '${visit.winesCount} ${visit.winesCount == 1 ? 'tasting' : 'tastings'}',
                                  style: TextStyle(
                                      fontSize: 11, color: cs.outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Rating
                      if (rating != null)
                        RatingStars(rating: rating, size: 14),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 16, color: cs.outline),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
