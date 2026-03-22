import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/palate_provider.dart';

class PalateScreen extends ConsumerWidget {
  const PalateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palateState = ref.watch(palateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Palate')),
      body: palateState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Visit stats
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Visit Stats',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _StatRow('Total Visits',
                        '${data.visitStats['total_visits'] ?? 0}'),
                    _StatRow(
                        'Avg Overall',
                        (data.visitStats['avg_overall'] as num?)
                                ?.toStringAsFixed(1) ??
                            '-'),
                    _StatRow(
                        'Avg Staff',
                        (data.visitStats['avg_staff'] as num?)
                                ?.toStringAsFixed(1) ??
                            '-'),
                    _StatRow(
                        'Avg Ambience',
                        (data.visitStats['avg_ambience'] as num?)
                                ?.toStringAsFixed(1) ??
                            '-'),
                    _StatRow(
                        'Avg Food',
                        (data.visitStats['avg_food'] as num?)
                                ?.toStringAsFixed(1) ??
                            '-'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Preferences
            if (data.profile.preferences.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Taste Profile',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      ...data.profile.preferences.entries.map(
                        (e) => _StatRow(
                          e.key
                              .replaceAll('_', ' ')
                              .split(' ')
                              .map((w) =>
                                  w[0].toUpperCase() + w.substring(1))
                              .join(' '),
                          '${e.value}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Top varietals
            if (data.topVarietals.isNotEmpty) ...[
              Text('Top Varietals',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...data.topVarietals.map((v) => ListTile(
                    leading: const Icon(Icons.local_drink),
                    title: Text(v['varietal'] as String? ?? ''),
                    subtitle: Text('${v['count']} wines tasted'),
                    trailing: Text(
                      (v['avg_rating'] as num?)?.toStringAsFixed(1) ?? '-',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  )),
            ],
            if (data.topVarietals.isEmpty && data.profile.preferences.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.insights,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        'Your palate profile will be generated after you log more wine tastings',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
