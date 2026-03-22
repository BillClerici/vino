import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/rating_stars.dart';
import '../../../core/widgets/wine_card.dart';
import '../providers/visits_provider.dart';

class VisitDetailScreen extends ConsumerWidget {
  final String visitId;
  const VisitDetailScreen({super.key, required this.visitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitState = ref.watch(visitDetailProvider(visitId));

    return Scaffold(
      appBar: AppBar(title: const Text('Visit Details')),
      body: visitState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (visit) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(visit.place?.name ?? 'Unknown',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(visit.visitedAt.substring(0, 10)),
                    const SizedBox(height: 12),
                    _RatingRow('Overall', visit.ratingOverall),
                    _RatingRow('Staff', visit.ratingStaff),
                    _RatingRow('Ambience', visit.ratingAmbience),
                    _RatingRow('Food', visit.ratingFood),
                    if (visit.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(visit.notes),
                    ],
                  ],
                ),
              ),
            ),
            if (visit.winesTasted != null &&
                visit.winesTasted!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Wines Tasted',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...visit.winesTasted!.map((wine) => WineCard(wine: wine)),
            ],
          ],
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String label;
  final int? rating;
  const _RatingRow(this.label, this.rating);

  @override
  Widget build(BuildContext context) {
    if (rating == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          RatingStars(rating: rating, size: 16),
        ],
      ),
    );
  }
}
