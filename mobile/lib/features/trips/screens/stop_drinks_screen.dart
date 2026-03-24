import 'dart:io' show File;
import 'dart:ui' show PointerDeviceKind;

import 'package:dio/dio.dart' show FormData, MultipartFile, Options;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../config/env.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/place.dart';
import '../../../core/providers/lookup_provider.dart';
import '../../../core/widgets/rating_stars.dart';

/// Dedicated drinks management page for a trip stop.
/// Shows the place drink menu at top, detailed drink cards, and a FAB to add new drinks.
class StopDrinksScreen extends ConsumerStatefulWidget {
  final String tripId;
  final String visitId;
  final Place place;
  final List<dynamic> existingWines;

  const StopDrinksScreen({
    super.key,
    required this.tripId,
    required this.visitId,
    required this.place,
    required this.existingWines,
  });

  @override
  ConsumerState<StopDrinksScreen> createState() => _StopDrinksScreenState();
}

class _StopDrinksScreenState extends ConsumerState<StopDrinksScreen> {
  late final List<Map<String, dynamic>> _drinks;
  List<Map<String, dynamic>>? _menuItems;
  bool _fetchingMenu = false;
  Set<String> _wishlistedNames = {};

  @override
  void initState() {
    super.initState();
    _drinks = widget.existingWines.map((w) {
      final wine = w as Map<String, dynamic>;
      return <String, dynamic>{
        'id': wine['id'] ?? '',
        'wine_name': wine['display_name'] ?? wine['wine_name'] ?? '',
        'wine_type': wine['wine_type'] ?? '',
        'serving_type': wine['serving_type'] ?? '',
        'rating': wine['rating'],
        'tasting_notes': wine['tasting_notes'] ?? '',
        'rating_comments': wine['rating_comments'] ?? '',
        'is_favorite': wine['is_favorite'] ?? false,
        'purchased': wine['purchased'] ?? false,
        'purchased_price': wine['purchased_price'],
        'purchased_quantity': wine['purchased_quantity'],
        'photo': wine['photo'] ?? '',
        'quantity': wine['quantity'] ?? 1,
        'menu_item': wine['menu_item'],
      };
    }).toList();
    _loadMenu();
    _loadWishlist();
  }

  String get _placeType => widget.place.placeType;

  Future<void> _loadMenu() async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.get(
        '${ApiPaths.places}${widget.place.id}/menu/',
        queryParameters: {'page_size': '100'},
      );
      final data = resp.data['data'] as List<dynamic>? ?? [];
      if (data.isNotEmpty && mounted) {
        setState(() {
          _menuItems = data.map((e) => e as Map<String, dynamic>).toList();
        });
      } else if (mounted) {
        setState(() => _menuItems = []);
      }
    } catch (_) {
      if (mounted) setState(() => _menuItems = []);
    }
  }

  Future<void> _loadWishlist() async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.get(ApiPaths.wishlistCheck(widget.place.id));
      final data = resp.data['data'] as Map<String, dynamic>? ??
          resp.data as Map<String, dynamic>;
      final names = <String>{};
      for (final m in (data['direct_matches'] as List?) ?? []) {
        final n = (m is Map ? m['wine_name'] : m) as String?;
        if (n != null && n.isNotEmpty) names.add(n.toLowerCase());
      }
      for (final m in (data['name_matches'] as List?) ?? []) {
        final n = (m as Map)['menu_item_name'] as String?;
        if (n != null) names.add(n.toLowerCase());
      }
      if (mounted) setState(() => _wishlistedNames = names);
    } catch (_) {}
  }

  Future<void> _fetchMenuFromWebsite() async {
    setState(() => _fetchingMenu = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post(
        '${ApiPaths.places}${widget.place.id}/fetch-menu/',
        data: {'force': false},
        options: Options(receiveTimeout: const Duration(minutes: 3)),
      );
      final data = resp.data['data'] as Map<String, dynamic>;
      final items = (data['menu_items'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      setState(() {
        _menuItems = items;
        _fetchingMenu = false;
      });
      if (items.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No menu items found on website')),
        );
      }
    } catch (e) {
      setState(() => _fetchingMenu = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching menu: $e')),
        );
      }
    }
  }

  Future<String?> _uploadPhoto(String drinkId, XFile photo) async {
    try {
      final api = ref.read(apiClientProvider);
      final MultipartFile file;
      if (kIsWeb) {
        final bytes = await photo.readAsBytes();
        file = MultipartFile.fromBytes(bytes, filename: 'photo.jpg');
      } else {
        file = await MultipartFile.fromFile(photo.path, filename: 'photo.jpg');
      }
      final formData = FormData.fromMap({'file': file});
      final resp = await api.dio.post(
        ApiPaths.winePhoto(widget.visitId, drinkId),
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      final data = resp.data is Map ? resp.data : (resp.data as dynamic);
      final nested = data['data'] as Map<String, dynamic>?;
      return (nested?['photo_url'] ?? data['photo_url']) as String?;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _addDrink({Map<String, dynamic>? prefill}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _DrinkFormSheet(
          initial: prefill,
          menuItems: widget.place.menuItems ?? [],
          placeType: _placeType,
          title: prefill != null ? 'Add ${prefill['wine_name']}' : 'Add Drink',
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      final api = ref.read(apiClientProvider);
      final pickedPhoto = result.remove('_picked_photo') as XFile?;
      final menuItemId = prefill?['menu_item'];
      final resp = await api.post(
        '${ApiPaths.trips}${widget.tripId}/live/wine/',
        data: {
          ...result,
          'visit_id': widget.visitId,
          if (menuItemId != null) 'menu_item': menuItemId,
        },
      );
      final respData = resp.data['data'] as Map<String, dynamic>?;
      final drinkId = respData?['id'] as String? ?? '';

      String? photoUrl;
      if (pickedPhoto != null && drinkId.isNotEmpty) {
        photoUrl = await _uploadPhoto(drinkId, pickedPhoto);
      }

      setState(() {
        _drinks.add({
          ...result,
          'id': drinkId,
          'quantity': 1,
          if (menuItemId != null) 'menu_item': menuItemId,
          if (photoUrl != null && photoUrl.isNotEmpty) 'photo': photoUrl,
        });
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drink added!'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addFromMenu(Map<String, dynamic> menuItem) async {
    final prefill = <String, dynamic>{
      'wine_name': menuItem['name'] ?? '',
      'wine_type': menuItem['varietal'] ?? '',
      'tasting_notes': menuItem['description'] ?? '',
      'menu_item': menuItem['id'],
    };
    await _addDrink(prefill: prefill);
  }

  Future<void> _updateQuantity(int index, int newQty) async {
    final drink = _drinks[index];
    final drinkId = drink['id'] as String? ?? '';
    if (drinkId.isEmpty || newQty < 1) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.patch(
        '${ApiPaths.visits}${widget.visitId}/wines/$drinkId/',
        data: {'quantity': newQty},
      );
      setState(() => _drinks[index]['quantity'] = newQty);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editDrink(int index) async {
    final drink = Map<String, dynamic>.from(_drinks[index]);
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _DrinkFormSheet(
          initial: drink,
          menuItems: widget.place.menuItems ?? [],
          placeType: _placeType,
          title: 'Edit Drink',
        ),
      ),
    );
    if (result == null || !mounted) return;

    final drinkId = drink['id'] as String? ?? '';
    if (drinkId.isNotEmpty) {
      try {
        final api = ref.read(apiClientProvider);
        final pickedPhoto = result.remove('_picked_photo') as XFile?;
        await api.patch('${ApiPaths.visits}${widget.visitId}/wines/$drinkId/', data: result);

        String? photoUrl = result['photo'] as String?;
        if (pickedPhoto != null) {
          photoUrl = await _uploadPhoto(drinkId, pickedPhoto);
        }

        setState(() => _drinks[index] = {
              ...result,
              'id': drinkId,
              'quantity': drink['quantity'] ?? 1,
              if (drink['menu_item'] != null) 'menu_item': drink['menu_item'],
              if (photoUrl != null && photoUrl.isNotEmpty) 'photo': photoUrl,
            });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Drink updated'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _deleteDrink(int index) async {
    final drink = _drinks[index];
    final drinkId = drink['id'] as String?;
    if (drinkId == null || drinkId.isEmpty) {
      setState(() => _drinks.removeAt(index));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Drink?'),
        content: Text('Remove "${drink['wine_name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.delete('${ApiPaths.visits}${widget.visitId}/wines/$drinkId/');
      if (mounted) {
        setState(() => _drinks.removeAt(index));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drink removed'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final drinkLabel = _placeType == 'brewery' ? 'Beer' : 'Drink';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Drinks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.place.name, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner),
            tooltip: 'Scan Label',
            onPressed: () => _addDrink(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDrink(),
        icon: const Icon(Icons.add),
        label: Text('Add $drinkLabel'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // ── Drink Menu Section ──
          _buildMenuSection(cs),

          const SizedBox(height: 20),

          // ── My Drinks Header ──
          Row(
            children: [
              Icon(Icons.local_bar, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Drinks Tasted (${_drinks.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Drink Cards ──
          if (_drinks.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.local_drink, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      const Text('No drinks logged yet', style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Tap "+ Add $drinkLabel" to get started',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ),
            )
          else
            ...List.generate(_drinks.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DetailedDrinkCard(
                  drink: _drinks[i],
                  placeType: _placeType,
                  onEdit: () => _editDrink(i),
                  onDelete: () => _deleteDrink(i),
                  onQuantityChanged: (qty) => _updateQuantity(i, qty),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildMenuSection(ColorScheme cs) {
    final hasMenu = _menuItems != null && _menuItems!.isNotEmpty;
    final hasWebsite = widget.place.website.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: Colors.amber),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                hasMenu ? 'Drink Menu (${_menuItems!.length})' : 'Drink Menu',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (hasMenu)
              TextButton.icon(
                onPressed: _fetchingMenu ? null : _fetchMenuFromWebsite,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Refresh', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_menuItems == null)
          const Center(child: Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else if (!hasMenu && hasWebsite)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _fetchingMenu ? null : _fetchMenuFromWebsite,
              icon: _fetchingMenu
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(_fetchingMenu ? 'Scanning website...' : 'Fetch Menu from Website',
                  style: const TextStyle(fontSize: 12)),
            ),
          )
        else if (!hasMenu)
          const Text('No menu available', style: TextStyle(color: Colors.grey, fontSize: 13))
        else
          SizedBox(
            height: 150,
            child: ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _menuItems!.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final item = _menuItems![i];
                  final itemName = (item['name'] as String? ?? '').toLowerCase();
                  return _MenuCard(
                    item: item,
                    wishlisted: _wishlistedNames.contains(itemName),
                    onTap: () => _addFromMenu(item),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// DETAILED DRINK CARD
// ═══════════════════════════════════════════════════════════════════

class _DetailedDrinkCard extends StatelessWidget {
  final Map<String, dynamic> drink;
  final String placeType;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<int> onQuantityChanged;

  const _DetailedDrinkCard({
    required this.drink,
    required this.placeType,
    required this.onEdit,
    required this.onDelete,
    required this.onQuantityChanged,
  });

  void _showFullImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(imageUrl, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64)),
              ),
            ),
            Positioned(
              top: 16, right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = drink['wine_name'] as String? ?? '';
    final type = drink['wine_type'] as String? ?? '';
    final serving = drink['serving_type'] as String? ?? '';
    final rating = drink['rating'] as int?;
    final notes = drink['tasting_notes'] as String? ?? '';
    final ratingComments = drink['rating_comments'] as String? ?? '';
    final isFavorite = drink['is_favorite'] as bool? ?? false;
    final purchased = drink['purchased'] as bool? ?? false;
    final price = drink['purchased_price'];
    final qty = drink['purchased_quantity'];
    final quantity = (drink['quantity'] as int?) ?? 1;
    final photo = drink['photo'] as String? ?? '';
    final hasImage = photo.isNotEmpty;

    String displayImage = photo;
    if (kIsWeb && hasImage && (photo.contains('vinoshipper') || photo.contains('s3.amazonaws'))) {
      displayImage = '${EnvConfig.apiBaseUrl}/api/v1/image-proxy/?url=${Uri.encodeComponent(photo)}';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header with image ──
          if (hasImage)
            GestureDetector(
              onTap: () => _showFullImage(context, displayImage),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.network(
                  displayImage,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 80,
                    color: cs.primaryContainer.withValues(alpha: 0.3),
                    child: Center(child: Icon(Icons.local_drink, size: 32, color: cs.primary.withValues(alpha: 0.4))),
                  ),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Name + Badges row ──
                Row(
                  children: [
                    if (!hasImage) ...[
                      CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        radius: 20,
                        child: Icon(
                          placeType == 'brewery' ? Icons.sports_bar : Icons.wine_bar,
                          size: 20,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                              if (quantity > 1) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('x$quantity',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [type, serving].where((s) => s.isNotEmpty).join(' · '),
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    if (isFavorite)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.favorite, color: Colors.red, size: 20),
                      ),
                    if (purchased)
                      const Icon(Icons.shopping_bag, color: Colors.green, size: 20),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Rating ──
                if (rating != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RatingStars(rating: rating, size: 22),
                  ),

                // ── Tasting notes ──
                if (notes.isNotEmpty) ...[
                  Text('Tasting Notes',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text(notes, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                ],

                // ── Rating comments ──
                if (ratingComments.isNotEmpty) ...[
                  Text('Comments',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text(ratingComments, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                ],

                // ── Purchase info ──
                if (purchased)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_bag, size: 14, color: Colors.green),
                        const SizedBox(width: 6),
                        Text(
                          [
                            'Purchased',
                            if (qty != null) '($qty)',
                            if (price != null) '— \$$price',
                          ].join(' '),
                          style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),

                const Divider(height: 20),

                // ── Quantity stepper + actions ──
                Row(
                  children: [
                    // Quantity stepper
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: quantity > 1 ? () => onQuantityChanged(quantity - 1) : null,
                            icon: const Icon(Icons.remove, size: 18),
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            padding: EdgeInsets.zero,
                            tooltip: 'Decrease',
                          ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 32),
                            alignment: Alignment.center,
                            child: Text('$quantity',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            onPressed: () => onQuantityChanged(quantity + 1),
                            icon: const Icon(Icons.add, size: 18),
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            padding: EdgeInsets.zero,
                            tooltip: 'Have another',
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Edit button
                    IconButton(
                      onPressed: onEdit,
                      icon: Icon(Icons.edit_outlined, size: 20, color: cs.primary),
                      tooltip: 'Edit',
                      style: IconButton.styleFrom(
                        backgroundColor: cs.primaryContainer.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Delete button
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      tooltip: 'Remove',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// MENU CARD (for the horizontal carousel)
// ═══════════════════════════════════════════════════════════════════

class _MenuCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool wishlisted;
  final VoidCallback onTap;

  const _MenuCard({required this.item, required this.wishlisted, required this.onTap});

  String? _getImageUrl(String url) {
    if (url.isEmpty) return null;
    if (!kIsWeb) return url;
    return '${EnvConfig.apiBaseUrl}/api/v1/image-proxy/?url=${Uri.encodeComponent(url)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = item['name'] as String? ?? '';
    final varietal = item['varietal'] as String? ?? '';
    final vintage = item['vintage'];
    final price = item['price'];
    final rawImageUrl = item['image_url'] as String? ?? '';
    final imageUrl = _getImageUrl(rawImageUrl);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
          color: Theme.of(context).cardColor,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Stack(
              children: [
                SizedBox(
                  height: 75,
                  width: double.infinity,
                  child: imageUrl != null
                      ? Image.network(imageUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(cs))
                      : _placeholder(cs),
                ),
                if (wishlisted)
                  Positioned(
                    top: 2, right: 2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.bookmark, size: 14, color: cs.secondary),
                    ),
                  ),
                // "Add" overlay
                Positioned(
                  bottom: 4, right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 14, color: Colors.white),
                  ),
                ),
              ],
            ),
            // Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(name,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    if (varietal.isNotEmpty)
                      Text(
                        [varietal, if (vintage != null) '$vintage'].join(' '),
                        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    if (price != null)
                      Text('\$$price',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.primary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      color: cs.primaryContainer.withValues(alpha: 0.3),
      child: Center(
        child: Icon(Icons.local_drink, size: 24, color: cs.primary.withValues(alpha: 0.4)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// DRINK FORM BOTTOM SHEET (reused from stop detail)
// ═══════════════════════════════════════════════════════════════════

class _DrinkFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initial;
  final List<MenuItem> menuItems;
  final String placeType;
  final String title;

  const _DrinkFormSheet({
    this.initial,
    required this.menuItems,
    required this.placeType,
    required this.title,
  });

  @override
  ConsumerState<_DrinkFormSheet> createState() => _DrinkFormSheetState();
}

class _DrinkFormSheetState extends ConsumerState<_DrinkFormSheet> {
  String _toLabel(String value) {
    if (value.isEmpty) return 'Tasting';
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  late final TextEditingController _nameCtl;
  late final TextEditingController _notesCtl;
  late final TextEditingController _ratingCommentsCtl;
  late final TextEditingController _priceCtl;
  late String _type;
  late String _serving;
  late int? _rating;
  late bool _isFavorite;
  late bool _purchased;
  late int? _purchasedQty;
  XFile? _pickedPhoto;
  String? _existingPhotoUrl;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial ?? {};
    _nameCtl = TextEditingController(text: d['wine_name'] as String? ?? '');
    _notesCtl = TextEditingController(text: d['tasting_notes'] as String? ?? '');
    _ratingCommentsCtl = TextEditingController(text: d['rating_comments'] as String? ?? '');
    _priceCtl = TextEditingController(
      text: d['purchased_price'] != null ? '${d['purchased_price']}' : '',
    );
    final defaultType = widget.placeType == 'brewery' ? 'Lager' : 'Red';
    _type = (d['wine_type'] as String?) ?? defaultType;
    if (_type.isEmpty) _type = defaultType;
    _serving = _toLabel((d['serving_type'] as String?) ?? 'tasting');
    _rating = d['rating'] as int?;
    _isFavorite = d['is_favorite'] as bool? ?? false;
    _purchased = d['purchased'] as bool? ?? false;
    _purchasedQty = d['purchased_quantity'] as int?;
    final photo = d['photo'] as String? ?? '';
    _existingPhotoUrl = photo.isNotEmpty ? photo : null;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _notesCtl.dispose();
    _ratingCommentsCtl.dispose();
    _priceCtl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1200, imageQuality: 85);
    if (photo != null) setState(() { _pickedPhoto = photo; _existingPhotoUrl = null; });
  }

  Future<void> _scanLabel() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 1200, maxHeight: 1200, imageQuality: 85);
    if (photo == null || !mounted) return;
    setState(() { _scanning = true; _pickedPhoto = photo; _existingPhotoUrl = null; });
    try {
      final api = ref.read(apiClientProvider);
      final MultipartFile file;
      if (kIsWeb) {
        final bytes = await photo.readAsBytes();
        file = MultipartFile.fromBytes(bytes, filename: 'label.jpg');
      } else {
        file = await MultipartFile.fromFile(photo.path, filename: 'label.jpg');
      }
      final formData = FormData.fromMap({'file': file});
      final resp = await api.dio.post(ApiPaths.scanLabel, data: formData,
          options: Options(contentType: 'multipart/form-data'));
      final data = resp.data is Map ? resp.data as Map<String, dynamic> : <String, dynamic>{};
      final nested = data['data'] as Map<String, dynamic>? ?? data;
      if (mounted) {
        final name = nested['name'] as String? ?? '';
        final varietal = nested['varietal'] as String? ?? '';
        final description = nested['description'] as String? ?? '';
        setState(() {
          if (name.isNotEmpty) _nameCtl.text = name;
          if (varietal.isNotEmpty) _type = varietal;
          if (description.isNotEmpty) _notesCtl.text = description;
          _scanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(name.isNotEmpty ? 'Found: $name' : 'Could not read label clearly.'),
            backgroundColor: name.isNotEmpty ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildPhotoSection() {
    final hasPickedPhoto = _pickedPhoto != null;
    final hasExistingPhoto = _existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photo', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        if (hasPickedPhoto || hasExistingPhoto)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: hasPickedPhoto
                    ? kIsWeb
                        ? Image.network(_pickedPhoto!.path, height: 160, width: double.infinity, fit: BoxFit.cover)
                        : Image.file(File(_pickedPhoto!.path), height: 160, width: double.infinity, fit: BoxFit.cover)
                    : Image.network(_existingPhotoUrl!, height: 160, width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(height: 160, color: Colors.grey[200],
                            child: const Center(child: Icon(Icons.broken_image)))),
              ),
              Positioned(
                top: 4, right: 4,
                child: CircleAvatar(
                  radius: 14, backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 14, color: Colors.white),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() { _pickedPhoto = null; _existingPhotoUrl = null; }),
                  ),
                ),
              ),
            ],
          )
        else
          GestureDetector(
            onTap: () => _pickImage(ImageSource.camera),
            child: Container(
              height: 80, width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[50],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 28, color: Colors.grey[500]),
                  const SizedBox(height: 4),
                  Text('Add Photo', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt, size: 16),
              label: const Text('Camera', style: TextStyle(fontSize: 12)),
            ),
            TextButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library, size: 16),
              label: const Text('Gallery', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  void _done() {
    if (_nameCtl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drink name is required')));
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      'wine_name': _nameCtl.text,
      'wine_type': _type,
      'serving_type': _serving.toLowerCase().replaceAll(' ', '_'),
      'tasting_notes': _notesCtl.text,
      'rating': _rating,
      'rating_comments': _ratingCommentsCtl.text,
      'is_favorite': _isFavorite,
      'purchased': _purchased,
      'purchased_quantity': _purchased ? (_purchasedQty ?? 1) : null,
      'purchased_price': _purchased ? double.tryParse(_priceCtl.text) : null,
      'photo': _existingPhotoUrl ?? '',
      '_picked_photo': _pickedPhoto,
    });
  }

  @override
  Widget build(BuildContext context) {
    final codes = DrinkLookupCodes.forPlaceType(widget.placeType);
    final typeList = ref.watch(lookupProvider(codes.typeCode));
    final servingList = ref.watch(lookupProvider(codes.servingCode));

    final defaultType = widget.placeType == 'brewery' ? 'Lager' : 'Red';
    final defaultServing = 'Tasting';
    final typeOptions = typeList.when(
      data: (items) {
        final labels = items.map((l) => l.label).toList();
        return labels.isEmpty ? <String>[defaultType] : labels;
      },
      loading: () => <String>[defaultType],
      error: (_, __) => <String>[defaultType],
    );
    final servingOptions = servingList.when(
      data: (items) {
        final labels = items.map((l) => l.label).toList();
        return labels.isEmpty ? <String>[defaultServing] : labels;
      },
      loading: () => <String>[defaultServing],
      error: (_, __) => <String>[defaultServing],
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 12),
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // Scan Label
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _scanning ? null : _scanLabel,
                icon: _scanning
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.document_scanner),
                label: Text(_scanning ? 'Scanning label...' : 'Scan Label with AI'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Theme.of(context).colorScheme.secondary),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Quick pick from menu
            if (widget.menuItems.isNotEmpty) ...[
              Text('From Menu', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.menuItems.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final item = widget.menuItems[i];
                    return ActionChip(
                      label: Text(item.name, style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        _nameCtl.text = item.name;
                        if (item.varietal.isNotEmpty) setState(() => _type = item.varietal);
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 20),
            ],

            // Name
            TextField(controller: _nameCtl, decoration: const InputDecoration(labelText: 'Drink Name')),
            const SizedBox(height: 12),

            // Type + Serving
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: typeOptions.contains(_type) ? _type : typeOptions.first,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: typeOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: servingOptions.contains(_serving) ? _serving : servingOptions.first,
                    decoration: const InputDecoration(labelText: 'Serving'),
                    items: servingOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => _serving = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tasting notes
            TextField(controller: _notesCtl, maxLines: 2, decoration: const InputDecoration(labelText: 'Tasting Notes')),
            const SizedBox(height: 12),

            // Photo
            _buildPhotoSection(),
            const SizedBox(height: 12),

            // Rating comments
            TextField(controller: _ratingCommentsCtl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Rating Comments', hintText: 'What did you like or dislike?')),
            const SizedBox(height: 12),

            // Rating
            Row(
              children: [
                const Text('Rating: '),
                RatingStars(rating: _rating, size: 28, onChanged: (v) => setState(() => _rating = v)),
                if (_rating != null) ...[
                  const Spacer(),
                  TextButton(onPressed: () => setState(() => _rating = null),
                      child: const Text('Clear', style: TextStyle(fontSize: 12))),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Favorite
            SwitchListTile(
              title: const Text('Favorite'),
              secondary: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, color: _isFavorite ? Colors.red : null),
              value: _isFavorite,
              onChanged: (v) => setState(() => _isFavorite = v),
              contentPadding: EdgeInsets.zero,
            ),

            // Wishlist
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.bookmark_add_outlined, color: Theme.of(context).colorScheme.secondary),
              title: const Text('Add to Wishlist'),
              subtitle: const Text('Save to try again later', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              dense: true,
              onTap: () async {
                if (_nameCtl.text.isEmpty) return;
                try {
                  final api = ref.read(apiClientProvider);
                  await api.post(ApiPaths.wishlist, data: {'wine_name': _nameCtl.text, 'wine_type': _type});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${_nameCtl.text} added to wishlist!'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)),
                    );
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add to wishlist')));
                  }
                }
              },
            ),

            // Purchased
            SwitchListTile(
              title: Text(widget.placeType == 'brewery' ? 'Bought to go?' : 'Bought a bottle?'),
              secondary: const Icon(Icons.shopping_bag),
              value: _purchased,
              onChanged: (v) => setState(() => _purchased = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_purchased) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(controller: _priceCtl, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Price', prefixText: '\$')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _purchasedQty ?? 1,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      items: List.generate(12, (i) => i + 1).map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                      onChanged: (v) => setState(() => _purchasedQty = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _done,
                    child: Text(widget.initial != null ? 'Update Drink' : 'Add Drink'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
