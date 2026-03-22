import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';

final badgesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiPaths.badges);
  return resp.data['data'] as Map<String, dynamic>? ?? resp.data as Map<String, dynamic>;
});

class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(badgesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final badges = (data['badges'] as List?) ?? [];
          final earned = data['earned_count'] as int? ?? 0;
          final total = data['total_count'] as int? ?? badges.length;

          // Group by category
          final categories = <String, List<Map<String, dynamic>>>{};
          for (final b in badges) {
            final badge = b as Map<String, dynamic>;
            final cat = badge['category'] as String? ?? 'other';
            categories.putIfAbsent(cat, () => []).add(badge);
          }

          final categoryLabels = {
            'visits': 'Explorer',
            'wines': 'Wine & Beer',
            'trips': 'Trips',
            'ai': 'Sippy & AI',
            'ratings': 'Ratings',
            'purchases': 'Purchases',
          };

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary card
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text('$earned / $total',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Badges Earned',
                          style: TextStyle(color: Colors.grey[700])),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: total > 0 ? earned / total : 0,
                          minHeight: 8,
                          backgroundColor: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Badge categories
              ...categories.entries.map((entry) {
                final label = categoryLabels[entry.key] ?? entry.key;
                final categoryBadges = entry.value;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categoryBadges.map((badge) {
                        return _BadgeTile(badge: badge);
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final Map<String, dynamic> badge;
  const _BadgeTile({required this.badge});

  IconData _iconFromName(String name) {
    const map = {
      'local_drink': Icons.local_drink,
      'explore': Icons.explore,
      'travel_explore': Icons.travel_explore,
      'public': Icons.public,
      'repeat': Icons.repeat,
      'wine_bar': Icons.wine_bar,
      'local_bar': Icons.local_bar,
      'emoji_events': Icons.emoji_events,
      'workspace_premium': Icons.workspace_premium,
      'category': Icons.category,
      'psychology': Icons.psychology,
      'star': Icons.star,
      'favorite': Icons.favorite,
      'directions_car': Icons.directions_car,
      'map': Icons.map,
      'route': Icons.route,
      'auto_awesome': Icons.auto_awesome,
      'smart_toy': Icons.smart_toy,
      'bookmark': Icons.bookmark,
      'rate_review': Icons.rate_review,
      'thumb_up': Icons.thumb_up,
      'shopping_bag': Icons.shopping_bag,
      'inventory_2': Icons.inventory_2,
    };
    return map[name] ?? Icons.emoji_events;
  }

  @override
  Widget build(BuildContext context) {
    final earned = badge['earned'] as bool? ?? false;
    final name = badge['name'] as String? ?? '';
    final description = badge['description'] as String? ?? '';
    final iconName = badge['icon'] as String? ?? 'emoji_events';
    final progress = (badge['progress'] as num?)?.toDouble() ?? 0.0;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(_iconFromName(iconName),
                    color: earned ? Colors.amber : Colors.grey[400]),
                const SizedBox(width: 8),
                Expanded(child: Text(name)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description),
                const SizedBox(height: 12),
                if (!earned) ...[
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 4),
                  Text('${(progress * 100).toInt()}% complete',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ] else
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 6),
                      Text('Earned!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      },
      child: Container(
        width: 80,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: earned ? Colors.amber.withValues(alpha: 0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: earned ? Colors.amber.withValues(alpha: 0.5) : Colors.grey[300]!,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconFromName(iconName),
              size: 28,
              color: earned ? Colors.amber : Colors.grey[400],
            ),
            const SizedBox(height: 4),
            Text(name,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: earned ? Colors.grey[800] : Colors.grey[500],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (!earned && progress > 0) ...[
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: Colors.grey[300],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
