import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';

final cellarProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiPaths.cellar);
  return resp.data['data'] as Map<String, dynamic>? ?? resp.data as Map<String, dynamic>;
});

class CellarScreen extends ConsumerWidget {
  const CellarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cellarProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Cellar')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final stats = data['stats'] as Map<String, dynamic>? ?? {};
          final recent = (data['recent_purchases'] as List?) ?? [];
          final topPlaces = (data['top_places'] as List?) ?? [];
          final topVarietals = (data['top_varietals'] as List?) ?? [];

          final totalBottles = stats['total_bottles'] as int? ?? 0;
          final totalSpend = stats['total_spend'] as num? ?? 0;
          final uniqueWines = stats['unique_wines'] as int? ?? 0;
          final avgPrice = stats['avg_price'] as num?;

          if (totalBottles == 0) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('Your cellar is empty'),
                    const SizedBox(height: 8),
                    Text(
                      'When you buy wines during visits, they\'ll show up here',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }

          final colorScheme = Theme.of(context).colorScheme;

          return RefreshIndicator(
            onRefresh: () => ref.refresh(cellarProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Stats row
                Row(
                  children: [
                    _StatCard(
                      label: 'Bottles',
                      value: '$totalBottles',
                      icon: Icons.inventory_2,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    _StatCard(
                      label: 'Spent',
                      value: '\$${totalSpend.toStringAsFixed(0)}',
                      icon: Icons.attach_money,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    _StatCard(
                      label: 'Wines',
                      value: '$uniqueWines',
                      icon: Icons.wine_bar,
                      color: colorScheme.secondary,
                    ),
                    if (avgPrice != null) ...[
                      const SizedBox(width: 8),
                      _StatCard(
                        label: 'Avg Price',
                        value: '\$${avgPrice.toStringAsFixed(0)}',
                        icon: Icons.trending_up,
                        color: Colors.orange,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),

                // Top places by spend
                if (topPlaces.isNotEmpty) ...[
                  Text('Top Places', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...topPlaces.map((tp) {
                    final p = tp as Map<String, dynamic>;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        radius: 18,
                        child: Icon(Icons.place, size: 18, color: colorScheme.primary),
                      ),
                      title: Text(p['place_name'] as String? ?? '', style: const TextStyle(fontSize: 14)),
                      subtitle: Text('${p['bottle_count'] ?? 0} bottles',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      trailing: Text('\$${(p['total_spend'] as num?)?.toStringAsFixed(0) ?? '0'}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                    );
                  }),
                  const SizedBox(height: 20),
                ],

                // Top varietals
                if (topVarietals.isNotEmpty) ...[
                  Text('Favorite Varietals', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: topVarietals.map((tv) {
                      final v = tv as Map<String, dynamic>;
                      return Chip(
                        avatar: const Icon(Icons.wine_bar, size: 14),
                        label: Text(
                          '${v['varietal']} (${v['count']})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],

                // Recent purchases
                Text('Recent Purchases', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...recent.map((r) {
                  final purchase = r as Map<String, dynamic>;
                  final name = purchase['wine_name'] as String? ?? 'Unknown';
                  final type = purchase['wine_type'] as String? ?? '';
                  final qty = purchase['quantity'] as int? ?? 1;
                  final price = purchase['price'] as num?;
                  final placeName = purchase['place_name'] as String? ?? '';
                  final rating = purchase['rating'] as int?;
                  final isFav = purchase['is_favorite'] as bool? ?? false;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.secondaryContainer,
                        child: Icon(Icons.wine_bar, color: colorScheme.secondary),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (type.isNotEmpty)
                            Text(type, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          Row(
                            children: [
                              if (placeName.isNotEmpty)
                                Flexible(child: Text(placeName,
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                    overflow: TextOverflow.ellipsis)),
                              if (qty > 1) Text(' x$qty', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            ],
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (price != null)
                            Text('\$${price.toStringAsFixed(0)}',
                                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (rating != null) ...[
                                Icon(Icons.star, size: 12, color: Colors.amber),
                                Text('$rating', style: const TextStyle(fontSize: 11)),
                              ],
                              if (isFav)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.favorite, size: 12, color: Colors.red),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
              Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }
}
