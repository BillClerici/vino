import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/trip_service.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';

final historyMapProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiPaths.historyMap);
  return resp.data['data'] as Map<String, dynamic>? ??
      resp.data as Map<String, dynamic>;
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyMapProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Journey Map')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final places =
              (data['places'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final totalPlaces = data['total_places'] as int? ?? places.length;

          if (places.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('No visits yet'),
                    const SizedBox(height: 8),
                    Text('Check in at places to see them on your history map',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
            );
          }

          return _HistoryMap(places: places, totalPlaces: totalPlaces);
        },
      ),
    );
  }
}

class _HistoryMap extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> places;
  final int totalPlaces;
  const _HistoryMap({required this.places, required this.totalPlaces});

  @override
  ConsumerState<_HistoryMap> createState() => _HistoryMapState();
}

class _HistoryMapState extends ConsumerState<_HistoryMap> {
  GoogleMapController? _mapController;
  Map<String, dynamic>? _selectedPlace;

  Color _placeTypeColor(String? type) {
    switch (type) {
      case 'winery':
        return const Color(0xFF8E44AD);
      case 'brewery':
        return Colors.orange;
      case 'restaurant':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  BitmapDescriptor _markerHue(String? type) {
    switch (type) {
      case 'winery':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      case 'brewery':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case 'restaurant':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      default:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
  }

  Set<Marker> get _markers {
    return widget.places.map((p) {
      final lat = (p['latitude'] as num).toDouble();
      final lng = (p['longitude'] as num).toDouble();
      final name = p['name'] as String? ?? '';
      final visits = p['visit_count'] as int? ?? 0;
      final type = p['place_type'] as String?;

      return Marker(
        markerId: MarkerId(p['place_id'] as String),
        position: LatLng(lat, lng),
        icon: _markerHue(type),
        onTap: () {
          setState(() => _selectedPlace = p);
        },
      );
    }).toSet();
  }

  void _fitBounds() {
    if (_mapController == null || widget.places.isEmpty) return;

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final p in widget.places) {
      final lat = (p['latitude'] as num).toDouble();
      final lng = (p['longitude'] as num).toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      50,
    ));
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Map
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(
              (widget.places.first['latitude'] as num).toDouble(),
              (widget.places.first['longitude'] as num).toDouble(),
            ),
            zoom: 8,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
            Future.delayed(const Duration(milliseconds: 400), _fitBounds);
          },
          markers: _markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
          onTap: (_) => setState(() => _selectedPlace = null),
        ),

        // Stats badge (top-left)
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black.withValues(alpha: 0.15))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.place, size: 16, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text('${widget.totalPlaces} places visited',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary)),
              ],
            ),
          ),
        ),

        // Selected place card (bottom)
        if (_selectedPlace != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: _PlaceCard(
              place: _selectedPlace!,
              onClose: () => setState(() => _selectedPlace = null),
              onViewVisit: () {
                final visitId = _selectedPlace!['last_visit_id'] as String?;
                if (visitId != null) {
                  context.push('/visits/$visitId');
                }
              },
              onStartTrip: () {
                final placeId = _selectedPlace!['place_id'] as String?;
                final name = _selectedPlace!['name'] as String? ?? '';
                if (placeId != null) {
                  startTripFromPlace(
                    context: context,
                    ref: ref,
                    placeId: placeId,
                    placeName: name,
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final VoidCallback onClose;
  final VoidCallback onViewVisit;
  final VoidCallback onStartTrip;
  const _PlaceCard({required this.place, required this.onClose, required this.onViewVisit, required this.onStartTrip});

  Color _placeTypeColor(String? type) {
    switch (type) {
      case 'winery': return const Color(0xFF8E44AD);
      case 'brewery': return Colors.orange;
      case 'restaurant': return Colors.green;
      default: return Colors.blueGrey;
    }
  }

  IconData _placeTypeIcon(String? type) {
    switch (type) {
      case 'winery': return Icons.wine_bar;
      case 'brewery': return Icons.sports_bar;
      case 'restaurant': return Icons.restaurant;
      default: return Icons.place;
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = place['name'] as String? ?? '';
    final type = place['place_type'] as String?;
    final city = place['city'] as String? ?? '';
    final state = place['state'] as String? ?? '';
    final address = place['address'] as String? ?? '';
    final website = place['website'] as String? ?? '';
    final phone = place['phone'] as String? ?? '';
    final visits = place['visit_count'] as int? ?? 0;
    final lastVisited = place['last_visited'] as String?;
    final imageUrl = place['image_url'] as String? ?? '';
    final location = [city, state].where((s) => s.isNotEmpty).join(', ');
    final typeColor = _placeTypeColor(type);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 100,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl.isNotEmpty)
                    Image.network(imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [typeColor.withValues(alpha: 0.3), typeColor.withValues(alpha: 0.1)],
                            ),
                          ),
                          child: Center(child: Icon(_placeTypeIcon(type), size: 36, color: typeColor)),
                        ))
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [typeColor.withValues(alpha: 0.3), typeColor.withValues(alpha: 0.1)],
                        ),
                      ),
                      child: Center(child: Icon(_placeTypeIcon(type), size: 36, color: typeColor)),
                    ),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                      ),
                    ),
                  ),
                  // Close button
                  Positioned(
                    top: 4, right: 4,
                    child: IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      style: IconButton.styleFrom(backgroundColor: Colors.black26),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                  ),
                  // Name overlay
                  Positioned(
                    left: 12, bottom: 8, right: 40,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (location.isNotEmpty)
                          Text(location, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Details
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                // Stats row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_placeTypeIcon(type), size: 12, color: typeColor),
                          const SizedBox(width: 4),
                          Text('$visits visit${visits != 1 ? 's' : ''}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: typeColor)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (lastVisited != null)
                      Text('Last: ${_formatDate(lastVisited)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
                const SizedBox(height: 8),

                // Address, website, phone
                if (address.isNotEmpty)
                  _InfoRow(icon: Icons.place, text: address),
                if (website.isNotEmpty)
                  _InfoRow(
                    icon: Icons.language,
                    text: website.replaceAll('https://', '').replaceAll('http://', '').replaceAll(RegExp(r'/$'), ''),
                    onTap: () => launchUrl(Uri.parse(website)),
                    isLink: true,
                  ),
                if (phone.isNotEmpty)
                  _InfoRow(
                    icon: Icons.phone,
                    text: phone,
                    onTap: () => launchUrl(Uri.parse('tel:$phone')),
                    isLink: true,
                  ),

                const SizedBox(height: 8),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onViewVisit,
                        icon: const Icon(Icons.history, size: 16),
                        label: const Text('Last Visit', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onStartTrip,
                        icon: const Icon(Icons.directions_car, size: 16),
                        label: const Text('Start Trip', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
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
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    fontSize: 12,
                    color: isLink ? Theme.of(context).colorScheme.primary : Colors.grey[700],
                    decoration: isLink ? TextDecoration.underline : null,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
