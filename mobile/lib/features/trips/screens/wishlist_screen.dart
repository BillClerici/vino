import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';

final wishlistProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiPaths.wishlist);
  final data = resp.data['data'] as List? ?? resp.data['results'] as List? ?? [];
  return data.map((e) => e as Map<String, dynamic>).toList();
});

class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wishlistProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Wishlist')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_border, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('No wines on your wishlist yet'),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the bookmark icon on any drink menu item to save it for later',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(wishlistProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = items[i];
                final name = item['display_name'] as String? ??
                    item['wine_name'] as String? ??
                    'Unknown';
                final type = item['wine_type'] as String? ?? '';
                final vintage = item['wine_vintage'];
                final placeName = item['place_name'] as String?;
                final notes = item['notes'] as String? ?? '';
                final createdAt = item['created_at'] as String?;

                return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                      child: Icon(Icons.wine_bar, color: Theme.of(context).colorScheme.secondary),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (type.isNotEmpty || vintage != null)
                          Text(
                            [type, if (vintage != null) '$vintage'].where((s) => s.isNotEmpty).join(' · '),
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        if (placeName != null)
                          Text('From: $placeName',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        if (notes.isNotEmpty)
                          Text(notes,
                              style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Remove from Wishlist?'),
                            content: Text('Remove "$name" from your wishlist?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Remove', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        try {
                          final api = ref.read(apiClientProvider);
                          await api.delete(ApiPaths.wishlistDetail(item['id'] as String));
                        } catch (_) {}
                        ref.invalidate(wishlistProvider);
                      },
                    ),
                  );
              },
            ),
          );
        },
      ),
    );
  }
}
