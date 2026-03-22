import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/visit.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/empty_state.dart';
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
  bool _groupByPlace = true;

  void _changeSort(_SortOption option) {
    setState(() => _sort = option);
    ref.read(visitsProvider.notifier).setOrdering(option.ordering);
  }

  @override
  Widget build(BuildContext context) {
    final visitsState = ref.watch(visitsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('My Visits'),
        actions: [helpButton(context, routePrefix: '/visits')],
      ),
      body: Column(
        children: [
          VinoSearchBar(
            hint: 'Search visits...',
            onChanged: (q) => ref.read(visitsProvider.notifier).search(q),
          ),

          // Sort & Group controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                // Sort dropdown
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Sort by',
                      labelStyle: const TextStyle(fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<_SortOption>(
                        value: _sort,
                        isDense: true,
                        isExpanded: true,
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
                const SizedBox(width: 12),
                // Group by Place toggle
                FilterChip(
                  label: const Text('Group by Place',
                      style: TextStyle(fontSize: 12)),
                  selected: _groupByPlace,
                  onSelected: (v) => setState(() => _groupByPlace = v),
                  selectedColor: colorScheme.primaryContainer,
                  showCheckmark: true,
                  visualDensity: VisualDensity.compact,
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
                    icon: Icons.place,
                    title: 'No visits yet',
                    subtitle: 'Check in at a winery to get started',
                  );
                }
                if (_groupByPlace) {
                  return _GroupedVisitList(visits: paginated.items);
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(visitsProvider.future),
                  child: ListView.builder(
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

// ── Visit Card ───────────────────────────────────────────────────

class _VisitCard extends StatelessWidget {
  final VisitLog visit;
  const _VisitCard({required this.visit});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.place)),
        title: Text(visit.place?.name ?? 'Unknown Place'),
        subtitle: Text(
          '${visit.visitedAt.substring(0, 10)} - ${visit.winesCount} wines',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RatingStars(rating: visit.ratingOverall, size: 14),
            if (visit.place?.id != null) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 20),
                tooltip: 'Place Details',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    context.push('/explore/${visit.place!.id}'),
              ),
            ],
          ],
        ),
        onTap: () => context.push('/visits/${visit.id}'),
      ),
    );
  }
}

// ── Grouped by Place ─────────────────────────────────────────────

class _GroupedVisitList extends StatelessWidget {
  final List<VisitLog> visits;
  const _GroupedVisitList({required this.visits});

  @override
  Widget build(BuildContext context) {
    // Group visits by place ID
    final groups = <String, List<VisitLog>>{};
    final placeNames = <String, String>{};
    for (final visit in visits) {
      final placeId = visit.place?.id ?? 'unknown';
      groups.putIfAbsent(placeId, () => []).add(visit);
      placeNames.putIfAbsent(
          placeId, () => visit.place?.name ?? 'Unknown Place');
    }

    // Sort groups by place name
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => (placeNames[a] ?? '').compareTo(placeNames[b] ?? ''));

    return ListView.builder(
      itemCount: sortedKeys.length,
      itemBuilder: (context, i) {
        final placeId = sortedKeys[i];
        final placeName = placeNames[placeId]!;
        final placeVisits = groups[placeId]!;

        return _PlaceGroup(
          placeId: placeId,
          placeName: placeName,
          visits: placeVisits,
        );
      },
    );
  }
}

class _PlaceGroup extends StatelessWidget {
  final String placeId;
  final String placeName;
  final List<VisitLog> visits;
  const _PlaceGroup(
      {required this.placeId,
      required this.placeName,
      required this.visits});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Place header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.place, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    placeName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${visits.length} ${visits.length == 1 ? 'visit' : 'visits'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (placeId != 'unknown') ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.info_outline,
                        size: 20, color: colorScheme.primary),
                    tooltip: 'Place Details',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () =>
                        context.push('/explore/$placeId'),
                  ),
                ],
              ],
            ),
          ),
          // Visit rows
          ...visits.map((visit) => ListTile(
                dense: true,
                title: Text(
                  visit.visitedAt.substring(0, 10),
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  '${visit.winesCount} wines',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: RatingStars(rating: visit.ratingOverall, size: 14),
                onTap: () => context.push('/visits/${visit.id}'),
              )),
        ],
      ),
    );
  }
}
