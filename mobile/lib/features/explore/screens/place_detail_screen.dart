import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/place.dart';
import '../../../core/services/trip_service.dart';
import '../providers/places_provider.dart';

class PlaceDetailScreen extends ConsumerWidget {
  final String placeId;
  const PlaceDetailScreen({super.key, required this.placeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeState = ref.watch(placeDetailProvider(placeId));

    return placeState.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (place) => _PlaceDetailBody(place: place),
    );
  }
}

class _PlaceDetailBody extends ConsumerWidget {
  final Place place;
  const _PlaceDetailBody({required this.place});

  Color _typeColor() {
    switch (place.placeType) {
      case 'winery': return const Color(0xFF8E44AD);
      case 'brewery': return Colors.orange;
      case 'restaurant': return Colors.green;
      default: return Colors.blueGrey;
    }
  }

  IconData _typeIcon() {
    switch (place.placeType) {
      case 'winery': return Icons.wine_bar;
      case 'brewery': return Icons.sports_bar;
      case 'restaurant': return Icons.restaurant;
      default: return Icons.place;
    }
  }

  String get _location {
    final parts = [place.city, place.state].where((s) => s.isNotEmpty);
    return parts.join(', ');
  }

  void _openInMaps() {
    final query = place.address.isNotEmpty
        ? Uri.encodeComponent(place.address)
        : '${place.latitude},${place.longitude}';
    launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final typeColor = _typeColor();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero header
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(
                  place.isFavorited ? Icons.favorite : Icons.favorite_border,
                  color: place.isFavorited ? Colors.red : Colors.white,
                ),
                onPressed: () async {
                  final api = ref.read(apiClientProvider);
                  await api.post('${ApiPaths.places}${place.id}/favorite/');
                  ref.invalidate(placeDetailProvider(place.id));
                  ref.invalidate(favoritesProvider);
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (place.imageUrl.isNotEmpty)
                    Image.network(place.imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colorScheme.primary, typeColor],
                            ),
                          ),
                        ))
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [colorScheme.primary, typeColor],
                        ),
                      ),
                      child: Center(child: Icon(_typeIcon(), size: 60, color: Colors.white38)),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.2), Colors.black.withValues(alpha: 0.7)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16, right: 16, bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Type badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: typeColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_typeIcon(), size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                place.placeType.isNotEmpty
                                    ? place.placeType[0].toUpperCase() + place.placeType.substring(1)
                                    : 'Place',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(place.name,
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
                        if (_location.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.place, size: 14, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text(_location, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats row
                  Row(
                    children: [
                      if (place.avgRating != null) ...[
                        const Icon(Icons.star, size: 18, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text('${place.avgRating!.toStringAsFixed(1)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 16),
                      ],
                      Icon(Icons.check_circle, size: 16, color: Colors.green[400]),
                      const SizedBox(width: 4),
                      Text('${place.visitCount} visit${place.visitCount != 1 ? 's' : ''}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                    ],
                  ),

                  // Description
                  if (place.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(place.description, style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.5)),
                  ],

                  // Contact info card
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey[200]!),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          if (place.address.isNotEmpty)
                            _InfoRow(
                              icon: Icons.place,
                              text: place.address,
                              onTap: _openInMaps,
                              isLink: true,
                            ),
                          if (place.phone.isNotEmpty)
                            _InfoRow(
                              icon: Icons.phone,
                              text: place.phone,
                              onTap: () => launchUrl(Uri.parse('tel:${place.phone}')),
                              isLink: true,
                            ),
                          if (place.website.isNotEmpty)
                            _InfoRow(
                              icon: Icons.language,
                              text: place.website.replaceAll('https://', '').replaceAll('http://', '').replaceAll(RegExp(r'/$'), ''),
                              onTap: () => launchUrl(Uri.parse(place.website)),
                              isLink: true,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Action buttons
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => startTripFromPlace(
                            context: context,
                            ref: ref,
                            placeId: place.id,
                            placeName: place.name,
                          ),
                          icon: const Icon(Icons.directions_car, size: 18),
                          label: const Text('Start Trip'),
                        ),
                      ),
                      if (place.address.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _openInMaps,
                          icon: const Icon(Icons.directions, size: 18),
                          label: const Text('Directions'),
                        ),
                      ],
                    ],
                  ),

                  // Menu items
                  if (place.menuItems != null && place.menuItems!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Drink Menu (${place.menuItems!.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...place.menuItems!.map((item) => Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey[200]!),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(child: Icon(_typeIcon(), size: 18, color: typeColor)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  if (item.varietal.isNotEmpty)
                                    Text(
                                      [item.varietal, if (item.vintage != null) '${item.vintage}'].join(' · '),
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                ],
                              ),
                            ),
                            if (item.price != null)
                              Text('\$${item.price!.toStringAsFixed(0)}',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                          ],
                        ),
                      ),
                    )),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool isLink;
  const _InfoRow({required this.icon, required this.text, this.onTap, this.isLink = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[500]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    fontSize: 13,
                    color: isLink ? Theme.of(context).colorScheme.primary : Colors.grey[700],
                    decoration: isLink ? TextDecoration.underline : null,
                  ),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            if (isLink)
              Icon(Icons.open_in_new, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
