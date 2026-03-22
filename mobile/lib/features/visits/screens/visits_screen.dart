import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/rating_stars.dart';
import '../../../core/widgets/search_bar.dart';
import '../providers/visits_provider.dart';

class VisitsScreen extends ConsumerWidget {
  const VisitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitsState = ref.watch(visitsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Visits')),
      body: Column(
        children: [
          VinoSearchBar(
            hint: 'Search visits...',
            onChanged: (q) => ref.read(visitsProvider.notifier).search(q),
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
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(visitsProvider.future),
                  child: ListView.builder(
                    itemCount: paginated.items.length,
                    itemBuilder: (_, i) {
                      final visit = paginated.items[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.place),
                          ),
                          title: Text(visit.place?.name ?? 'Unknown Place'),
                          subtitle: Text(
                            '${visit.visitedAt.substring(0, 10)} - ${visit.winesCount} wines',
                          ),
                          trailing: RatingStars(
                            rating: visit.ratingOverall,
                            size: 14,
                          ),
                          onTap: () =>
                              context.push('/visits/${visit.id}'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/visits/checkin'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
