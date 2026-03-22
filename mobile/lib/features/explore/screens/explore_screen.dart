import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../config/constants.dart';
import '../../../config/env.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/models/place.dart';
import '../../../core/services/google_places_service.dart';
import '../../../core/services/trip_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/place_card.dart';
import '../../../core/widgets/search_bar.dart';
import '../../help/help_launcher.dart';
import '../providers/places_provider.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Explore'),
        actions: [helpButton(context, routePrefix: '/explore')],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'List'),
            Tab(text: 'Map'),
            Tab(text: 'Favorites'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _PlaceListTab(),
          _PlaceMapTab(),
          _FavoritesTab(),
        ],
      ),
    );
  }
}

class _PlaceListTab extends ConsumerWidget {
  const _PlaceListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesState = ref.watch(placesProvider);

    return Column(
      children: [
        VinoSearchBar(
          hint: 'Search places...',
          onChanged: (q) => ref.read(placesProvider.notifier).search(q),
        ),
        Expanded(
          child: placesState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (paginated) {
              if (paginated.items.isEmpty) {
                return const EmptyState(
                  icon: Icons.explore,
                  title: 'No places found',
                );
              }
              return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollEndNotification &&
                      n.metrics.extentAfter < 200) {
                    ref.read(placesProvider.notifier).loadMore();
                  }
                  return false;
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: paginated.items.length,
                  itemBuilder: (_, i) {
                    final place = paginated.items[i];
                    return PlaceCard(
                      place: place,
                      onTap: () => context.push('/explore/${place.id}'),
                      onFavorite: () => ref
                          .read(placesProvider.notifier)
                          .toggleFavorite(place.id),
                      onStartTrip: () => startTripFromPlace(
                        context: context,
                        ref: ref,
                        placeId: place.id,
                        placeName: place.name,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaceMapTab extends ConsumerStatefulWidget {
  const _PlaceMapTab();

  @override
  ConsumerState<_PlaceMapTab> createState() => _PlaceMapTabState();
}

class _PlaceMapTabState extends ConsumerState<_PlaceMapTab>
    with AutomaticKeepAliveClientMixin {
  final _placesService = GooglePlacesService();
  final _searchCtl = TextEditingController();
  GoogleMapController? _mapController;
  List<Map<String, dynamic>> _places = [];
  Map<String, dynamic>? _selectedPlace;
  String _placeType = 'winery';
  bool _loading = false;
  Set<Marker> _markers = {};
  Timer? _mapIdleTimer;
  bool _initialSearchDone = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _search(fitMap: false);
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _mapIdleTimer?.cancel();
    super.dispose();
  }

  Future<void> _search({bool fitMap = true}) async {
    setState(() => _loading = true);
    try {
      final query = _searchCtl.text.isNotEmpty
          ? _searchCtl.text
          : _typeLabel(_placeType);
      final results = await _placesService.textSearch(query, type: _placeType);
      setState(() {
        _places = results;
        _loading = false;
        _buildMarkers();
      });
      if (fitMap && _markers.isNotEmpty && _mapController != null) {
        Future.delayed(const Duration(milliseconds: 200), _fitBounds);
      }
      _initialSearchDone = true;
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _searchNearby() async {
    if (_mapController == null) return;
    final bounds = await _mapController!.getVisibleRegion();
    final centerLat =
        (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
    final centerLng =
        (bounds.northeast.longitude + bounds.southwest.longitude) / 2;
    final latDiff =
        (bounds.northeast.latitude - bounds.southwest.latitude).abs();
    final radiusMeters = (latDiff * 111 * 1000 / 2).clamp(500, 50000).toDouble();

    setState(() => _loading = true);
    try {
      final results = await _placesService.nearbySearch(
        lat: centerLat,
        lng: centerLng,
        radiusMeters: radiusMeters,
        type: _placeType,
      );
      if (results.isNotEmpty) {
        setState(() {
          _places = results;
          _loading = false;
          _buildMarkers();
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _onCameraIdle() {
    if (!_initialSearchDone) return;
    _mapIdleTimer?.cancel();
    _mapIdleTimer = Timer(const Duration(milliseconds: 800), () {
      if (_searchCtl.text.isEmpty) _searchNearby();
    });
  }

  void _buildMarkers() {
    _markers = {};
    for (int i = 0; i < _places.length; i++) {
      final p = _places[i];
      final lat = _toDouble(p['latitude']);
      final lng = _toDouble(p['longitude']);
      if (lat == null || lng == null) continue;
      _markers.add(Marker(
        markerId: MarkerId(p['google_place_id'] as String? ?? 'place_$i'),
        position: LatLng(lat, lng),
        icon: _markerIcon(_placeType),
        onTap: () => setState(() => _selectedPlace = p),
      ));
    }
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  void _fitBounds() {
    if (_markers.isEmpty) return;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final m in _markers) {
      if (m.position.latitude < minLat) minLat = m.position.latitude;
      if (m.position.latitude > maxLat) maxLat = m.position.latitude;
      if (m.position.longitude < minLng) minLng = m.position.longitude;
      if (m.position.longitude > maxLng) maxLng = m.position.longitude;
    }
    if (minLat == maxLat) { minLat -= 0.05; maxLat += 0.05; }
    if (minLng == maxLng) { minLng -= 0.05; maxLng += 0.05; }
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng)),
      60,
    ));
  }

  Future<void> _viewPlaceDetails(BuildContext context) async {
    if (_selectedPlace == null) return;
    final p = _selectedPlace!;
    setState(() => _selectedPlace = null);

    try {
      // Save to DB (find-or-create) to get an ID for navigation
      final api = ref.read(apiClientProvider);
      var name = (p['name'] as String? ?? '').trim();
      if (name.isEmpty) name = 'Unknown Place';
      final address = (p['address'] as String? ?? '').trim();
      var website = (p['website'] as String? ?? '').trim();
      if (website.isNotEmpty && !website.startsWith('http')) {
        website = 'https://$website';
      }

      final placeData = <String, dynamic>{
        'name': name,
        'place_type': _placeType,
        'address': address,
        'city': (p['city'] as String? ?? '').trim(),
        'state': (p['state'] as String? ?? '').trim(),
        'website': website,
        'phone': (p['phone'] as String? ?? '').trim(),
      };
      final lat = p['latitude'];
      final lng = p['longitude'];
      if (lat != null) {
        final v = lat is double ? lat : double.tryParse('$lat');
        if (v != null) placeData['latitude'] = double.parse(v.toStringAsFixed(6));
      }
      if (lng != null) {
        final v = lng is double ? lng : double.tryParse('$lng');
        if (v != null) placeData['longitude'] = double.parse(v.toStringAsFixed(6));
      }

      final resp = await api.post(ApiPaths.places, data: placeData);
      final id = (resp.data['data'] as Map<String, dynamic>)['id'] as String;
      if (context.mounted) {
        context.push('/explore/$id');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _setFilter(String type) {
    setState(() {
      _placeType = type;
      _selectedPlace = null;
    });
    _search();
  }

  BitmapDescriptor _markerIcon(String type) {
    switch (type) {
      case 'brewery':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case 'restaurant':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      default:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'brewery': return 'breweries';
      case 'restaurant': return 'restaurants';
      default: return 'wineries';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _searchCtl,
            decoration: InputDecoration(
              hintText: 'Search by name, city...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtl.clear();
                        _search();
                      })
                  : null,
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none),
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _search(),
          ),
        ),

        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _ExploreFilterChip(
                label: 'Wineries', icon: Icons.local_drink,
                selected: _placeType == 'winery',
                onTap: () => _setFilter('winery'),
              ),
              const SizedBox(width: 8),
              _ExploreFilterChip(
                label: 'Breweries', icon: Icons.sports_bar,
                selected: _placeType == 'brewery',
                onTap: () => _setFilter('brewery'),
              ),
              const SizedBox(width: 8),
              _ExploreFilterChip(
                label: 'Restaurants', icon: Icons.restaurant,
                selected: _placeType == 'restaurant',
                onTap: () => _setFilter('restaurant'),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ],
          ),
        ),

        // Map
        Expanded(
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                    target: LatLng(35.2271, -80.8431), zoom: 10),
                markers: _markers,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                onMapCreated: (c) {
                  _mapController = c;
                },
                onCameraIdle: _onCameraIdle,
                onTap: (_) {
                  if (_selectedPlace != null) {
                    setState(() => _selectedPlace = null);
                  }
                },
              ),
              if (_selectedPlace != null)
                Positioned(
                  left: 12, right: 12, bottom: 12,
                  child: _ExploreMapCardFromGoogle(
                    place: _selectedPlace!,
                    onViewDetails: () => _viewPlaceDetails(context),
                    onStartTrip: () {
                      final p = _selectedPlace!;
                      setState(() => _selectedPlace = null);
                      startTripFromGooglePlace(
                        context: context,
                        ref: ref,
                        place: p,
                        placeType: _placeType,
                      );
                    },
                    onClose: () => setState(() => _selectedPlace = null),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExploreFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ExploreFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : cs.onSurface),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : cs.onSurface,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}

class _ExploreMapCardFromGoogle extends StatelessWidget {
  final Map<String, dynamic> place;
  final VoidCallback onViewDetails;
  final VoidCallback onStartTrip;
  final VoidCallback onClose;
  const _ExploreMapCardFromGoogle({
    required this.place,
    required this.onViewDetails,
    required this.onStartTrip,
    required this.onClose,
  });

  String? get _photoUrl {
    final photos = place['photos'] as List<dynamic>?;
    if (photos != null && photos.isNotEmpty) {
      final photo = photos.first as Map<String, dynamic>;
      final name = photo['name'] as String?;
      if (name != null) {
        final key = EnvConfig.googleMapsApiKey;
        return 'https://places.googleapis.com/v1/$name/media?maxWidthPx=400&key=$key';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photo = _photoUrl;

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 100,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null)
                  Image.network(photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(cs))
                else
                  _placeholder(cs),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 4, right: 4,
                  child: IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    style: IconButton.styleFrom(backgroundColor: Colors.black38),
                  ),
                ),
                Positioned(
                  left: 12, bottom: 8, right: 40,
                  child: Text(place['name'] as String? ?? '',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(children: [
                  Icon(Icons.place, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(place['address'] as String? ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onViewDetails,
                      child: const Text('Details'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onStartTrip,
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('Start Trip'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cs.primary, const Color(0xFF5DADE2)]),
      ),
      child: const Center(
        child: Icon(Icons.storefront, size: 36, color: Colors.white54),
      ),
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favState = ref.watch(favoritesProvider);

    return favState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (favorites) {
        if (favorites.isEmpty) {
          return const EmptyState(
            icon: Icons.favorite,
            title: 'No Favorites Yet',
            subtitle: 'Favorite a place from a trip stop or the list tab',
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(favoritesProvider.future),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: favorites.length,
            itemBuilder: (_, i) {
              final place = favorites[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/explore/${place.id}'),
                  child: Row(
                    children: [
                      // Image
                      SizedBox(
                        width: 100,
                        height: 80,
                        child: place.imageUrl.isNotEmpty
                            ? Image.network(place.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      child: const Icon(Icons.storefront),
                                    ))
                            : Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                child: const Icon(Icons.storefront),
                              ),
                      ),
                      // Details
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(place.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(place.location,
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              Text(
                                  place.placeType.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      ),
                      // Actions
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.favorite,
                                color: Colors.red, size: 20),
                            tooltip: 'Remove Favorite',
                            onPressed: () async {
                              final api = ref.read(apiClientProvider);
                              await api.post(
                                  '${ApiPaths.places}${place.id}/favorite/');
                              ref.invalidate(favoritesProvider);
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.map,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary),
                            tooltip: 'Start Trip',
                            onPressed: () => startTripFromPlace(
                              context: context,
                              ref: ref,
                              placeId: place.id,
                              placeName: place.name,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Explore Map Place Card ──────────────────────────────────────

class _ExploreMapCard extends StatelessWidget {
  final Place place;
  final VoidCallback onViewDetails;
  final VoidCallback onStartTrip;
  final VoidCallback onClose;
  const _ExploreMapCard({
    required this.place,
    required this.onViewDetails,
    required this.onStartTrip,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 100,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (place.imageUrl.isNotEmpty)
                  Image.network(place.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(cs))
                else
                  _placeholder(cs),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    style: IconButton.styleFrom(backgroundColor: Colors.black38),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 8,
                  right: 40,
                  child: Text(place.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.place, size: 14, color: cs.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(place.location,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (place.avgRating != null)
                      Row(
                        children: [
                          Icon(Icons.star, size: 14, color: Colors.amber[700]),
                          const SizedBox(width: 2),
                          Text(place.avgRating!.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onViewDetails,
                        child: const Text('View Details'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onStartTrip,
                        icon: const Icon(Icons.map, size: 16),
                        label: const Text('Start Trip'),
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

  Widget _placeholder(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, const Color(0xFF5DADE2)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.storefront, size: 36, color: Colors.white54),
      ),
    );
  }
}
