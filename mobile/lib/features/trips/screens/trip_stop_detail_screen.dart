import 'dart:io' show File;
import 'dart:ui' show PointerDeviceKind;

import 'package:dio/dio.dart' show Dio, FormData, MultipartFile, Options;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../config/env.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/place.dart';
import '../../../core/models/trip.dart';
import '../../../core/providers/lookup_provider.dart';
import '../../../core/widgets/rating_stars.dart';
import '../../help/help_launcher.dart';
import '../providers/trips_provider.dart';
import '../widgets/flight_builder_button.dart';
import '../widgets/sippy_chat.dart';
import '../widgets/sippy_history.dart';
import '../widgets/trip_stop_drawer.dart';
import 'stop_drinks_screen.dart';
import 'trip_detail_screen.dart' show TripRouteMapScreen;

class TripStopDetailScreen extends ConsumerStatefulWidget {
  final String tripId;
  final int stopIndex;
  const TripStopDetailScreen({
    super.key,
    required this.tripId,
    required this.stopIndex,
  });

  @override
  ConsumerState<TripStopDetailScreen> createState() =>
      _TripStopDetailScreenState();
}

class _TripStopDetailScreenState extends ConsumerState<TripStopDetailScreen> {
  String? _visitId;
  bool _checkedIn = false;
  bool _isFavorited = false;
  bool _checkingIn = false;
  bool _checkedExisting = false;
  bool _showMap = true;
  Map<String, dynamic>? _existingVisitData;
  var _drinksSectionKey = GlobalKey<_DrinksSectionState>();

  @override
  void initState() {
    super.initState();
    _checkExistingVisit();
  }

  @override
  void didUpdateWidget(TripStopDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stopIndex != widget.stopIndex) {
      _checkedExisting = false;
      _checkedIn = false;
      _visitId = null;
      _existingVisitData = null;
      _showMap = true;
      _isFavorited = false;
      _checkExistingVisit();
    }
  }

  Future<void> _checkExistingVisit() async {
    final tripState = ref.read(tripDetailProvider(widget.tripId));
    final trip = tripState.valueOrNull;
    if (trip == null) return;
    final stops = trip.tripStops ?? [];
    if (widget.stopIndex >= stops.length) return;
    final place = stops[widget.stopIndex].place;
    final placeId = place?.id;
    if (placeId == null) return;

    try {
      final api = ref.read(apiClientProvider);

      // Check favorite state from place detail (properly annotated)
      try {
        final placeResp = await api.get('${ApiPaths.places}$placeId/');
        final placeData = placeResp.data['data'] as Map<String, dynamic>;
        if (placeData['is_favorited'] == true && mounted) {
          setState(() => _isFavorited = true);
        }
      } catch (_) {}

      final resp = await api.get(
        ApiPaths.visits,
        queryParameters: {'place': placeId, 'page_size': '1'},
      );
      final data = resp.data['data'] as List<dynamic>?;
      if (data != null && data.isNotEmpty) {
        final visit = data.first as Map<String, dynamic>;
        // Fetch full visit detail to get wines and ratings
        final detailResp = await api.get('${ApiPaths.visits}${visit['id']}/');
        final visitDetail = detailResp.data['data'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _visitId = visit['id'] as String;
            _checkedIn = true;
            _checkedExisting = true;
            _existingVisitData = visitDetail;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _checkedExisting = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripState = ref.watch(tripDetailProvider(widget.tripId));

    return tripState.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (trip) {
        // If we haven't checked for existing visits yet, do it now
        if (!_checkedExisting) {
          _checkExistingVisit();
        }

        final stops = trip.tripStops ?? [];
        if (widget.stopIndex >= stops.length) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Stop not found')),
          );
        }
        final stop = stops[widget.stopIndex];
        final place = stop.place;
        if (place == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Place not found')),
          );
        }
        return _StopView(
          trip: trip,
          stop: stop,
          place: place,
          stopIndex: widget.stopIndex,
          totalStops: stops.length,
          tripId: widget.tripId,
          visitId: _visitId,
          checkedIn: _checkedIn,
          checkingIn: _checkingIn,
          existingVisitData: _existingVisitData,
          showMap: _showMap,
          isFavorited: _isFavorited,
          onToggleMap: () => setState(() => _showMap = !_showMap),
          onCheckIn: () => _doCheckIn(stop),
          onToggleFavorite: () => _toggleFavorite(place),
          onNavigate: _navigateToStop,
          onRemoveStop: () => _removeStop(stop),
          onEditStop: () => _editStop(stop),
          onCompleteTrip: _completeTrip,
          onUncheckIn: _undoCheckIn,
          onRefreshVisit: _checkExistingVisit,
          drinksSectionKey: _drinksSectionKey,
        );
      },
    );
  }

  Future<void> _doCheckIn(TripStop stop) async {
    setState(() => _checkingIn = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post(
        '${ApiPaths.trips}${widget.tripId}/live/checkin/${stop.id}/',
      );
      final data = resp.data['data'] as Map<String, dynamic>;
      setState(() {
        _visitId = data['visit_id'] as String;
        _checkedIn = true;
        _checkingIn = false;
      });

      // Show wishlist matches notification
      final wishlistMatches = (data['wishlist_matches'] as List?)?.cast<String>() ?? [];
      if (wishlistMatches.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Wishlist match! This place has: ${wishlistMatches.join(", ")}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Nice!',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _checkingIn = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Check-in failed: $e')));
      }
    }
  }

  Future<void> _undoCheckIn() async {
    if (_visitId == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.delete('${ApiPaths.visits}$_visitId/');
      setState(() {
        _visitId = null;
        _checkedIn = false;
        _existingVisitData = null;
      });
      _drinksSectionKey = GlobalKey<_DrinksSectionState>();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Check-in removed. You can check in again.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _toggleFavorite(Place place) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post('${ApiPaths.places}${place.id}/favorite/');
      final data = resp.data['data'] as Map<String, dynamic>;
      final isFav = data['is_favorited'] as bool;
      if (mounted) {
        setState(() => _isFavorited = isFav);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFav
                ? '${place.name} added to favorites!'
                : '${place.name} removed from favorites'),
            backgroundColor: isFav ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _completeTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Trip'),
        content: const Text('Mark this trip as completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Complete', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.post('${ApiPaths.trips}${widget.tripId}/complete/');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip completed!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        ref.invalidate(tripDetailProvider(widget.tripId));
        context.go('/trips/${widget.tripId}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editStop(TripStop stop) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: Builder(builder: (_) {
          final tripData = ref.read(tripDetailProvider(widget.tripId)).valueOrNull;
          final stops = tripData?.tripStops ?? [];
          final nextStop = widget.stopIndex < stops.length - 1
              ? stops[widget.stopIndex + 1]
              : null;
          return _EditStopSheet(
            tripId: widget.tripId,
            stop: stop,
            nextStop: nextStop,
          );
        }),
      ),
    );
    if (result == true && mounted) {
      ref.invalidate(tripDetailProvider(widget.tripId));
    }
  }

  Future<void> _removeStop(TripStop stop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Stop'),
        content: Text(
          'Remove "${stop.place?.name ?? 'this stop'}" from the trip?\n\n'
          'This will also remove any check-ins, drinks, and ratings for this stop.',
        ),
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
    if (confirmed != true || !mounted) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.delete(
        '${ApiPaths.trips}${widget.tripId}/stops/${stop.id}/',
      );
      if (mounted) {
        // Hide the map first to prevent Google Maps iframe from
        // intercepting the navigation on web
        setState(() => _showMap = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${stop.place?.name ?? "Stop"} removed'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
        ref.invalidate(tripDetailProvider(widget.tripId));
        // Defer navigation to next frame so the map widget is fully disposed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/trips/${widget.tripId}');
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _navigateToStop(int newIndex) {
    context.go('/trips/${widget.tripId}/stop/$newIndex');
  }
}

class _StopView extends StatefulWidget {
  final Trip trip;
  final TripStop stop;
  final Place place;
  final int stopIndex;
  final int totalStops;
  final String tripId;
  final String? visitId;
  final bool checkedIn;
  final bool checkingIn;
  final Map<String, dynamic>? existingVisitData;
  final bool showMap;
  final bool isFavorited;
  final VoidCallback onToggleMap;
  final VoidCallback onCheckIn;
  final VoidCallback onToggleFavorite;
  final ValueChanged<int> onNavigate;
  final VoidCallback onRemoveStop;
  final VoidCallback onEditStop;
  final VoidCallback onCompleteTrip;
  final VoidCallback onUncheckIn;
  final VoidCallback onRefreshVisit;
  final GlobalKey<_DrinksSectionState> drinksSectionKey;

  const _StopView({
    required this.trip,
    required this.stop,
    required this.place,
    required this.stopIndex,
    required this.totalStops,
    required this.tripId,
    required this.visitId,
    required this.checkedIn,
    required this.checkingIn,
    this.existingVisitData,
    required this.showMap,
    required this.isFavorited,
    required this.onToggleMap,
    required this.onCheckIn,
    required this.onToggleFavorite,
    required this.onNavigate,
    required this.onRemoveStop,
    required this.onEditStop,
    required this.onCompleteTrip,
    required this.onUncheckIn,
    required this.onRefreshVisit,
    required this.drinksSectionKey,
  });

  @override
  State<_StopView> createState() => _StopViewState();
}

class _StopViewState extends State<_StopView> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Convenience accessors
  Trip get trip => widget.trip;
  TripStop get stop => widget.stop;
  Place get place => widget.place;
  int get stopIndex => widget.stopIndex;
  int get totalStops => widget.totalStops;
  String get tripId => widget.tripId;
  String? get visitId => widget.visitId;
  bool get checkedIn => widget.checkedIn;
  bool get checkingIn => widget.checkingIn;
  Map<String, dynamic>? get existingVisitData => widget.existingVisitData;
  bool get showMap => widget.showMap;
  bool get isFavorited => widget.isFavorited;
  VoidCallback get onToggleMap => widget.onToggleMap;
  VoidCallback get onCheckIn => widget.onCheckIn;
  VoidCallback get onToggleFavorite => widget.onToggleFavorite;
  ValueChanged<int> get onNavigate => widget.onNavigate;
  VoidCallback get onRemoveStop => widget.onRemoveStop;
  VoidCallback get onEditStop => widget.onEditStop;
  VoidCallback get onCompleteTrip => widget.onCompleteTrip;
  VoidCallback get onUncheckIn => widget.onUncheckIn;
  VoidCallback get onRefreshVisit => widget.onRefreshVisit;
  GlobalKey<_DrinksSectionState> get drinksSectionKey => widget.drinksSectionKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: TripStopDrawer(
        trip: trip,
        currentStopIndex: stopIndex,
        onNavigate: onNavigate,
        tripId: tripId,
        onEditStop: onEditStop,
        onDeleteStop: onRemoveStop,
        onShowRoute: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TripRouteMapScreen(trip: trip)),
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (checkedIn && visitId != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FloatingActionButton.extended(
                heroTag: 'drinks_fab',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: StopDrinksScreen(
                          tripId: tripId,
                          visitId: visitId!,
                          place: place,
                          existingWines: (existingVisitData?['wines_tasted'] as List<dynamic>?) ?? [],
                        ),
                      ),
                    ),
                  );
                  onRefreshVisit();
                },
                icon: const Icon(Icons.local_bar, size: 18),
                label: const Text('Drinks', style: TextStyle(fontWeight: FontWeight.bold)),
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          GestureDetector(
            onLongPress: () => openSippyHistory(context, tripId: tripId, chatType: 'ask'),
            child: FloatingActionButton.extended(
              heroTag: 'sippy_fab',
              onPressed: () => openSippyChat(context, tripId),
              tooltip: 'Ask Sippy (long-press for history)',
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Sippy', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ── Hero header with place image ──
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: Icon(
                  isFavorited ? Icons.favorite : Icons.favorite_border,
                  color: isFavorited ? Colors.red : Colors.white,
                ),
                tooltip: isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
                onPressed: onToggleFavorite,
              ),
              if (checkedIn)
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Undo Check-In?'),
                        content: const Text(
                          'This will remove your check-in and clear all drinks, ratings, and notes for this stop. You can check in again afterwards.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Undo Check-In'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) onUncheckIn();
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14),
                      SizedBox(width: 4),
                      Text('Checked In', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              // Trip navigation drawer toggle
              IconButton(
                icon: const Icon(Icons.menu_open),
                tooltip: 'Trip Stops',
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (place.imageUrl.isNotEmpty)
                    Image.network(place.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _gradientBg(colorScheme))
                  else
                    _gradientBg(colorScheme),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.5, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                  ),
                  // Stop info (bottom)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Badges row
                        Row(
                          children: [
                            _HeaderChip(
                              'Stop ${stopIndex + 1} of $totalStops',
                              filled: true,
                              color: Colors.white,
                              textColor: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            _HeaderChip(place.placeType.toUpperCase()),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Place name
                        Text(place.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                        if (place.location.isNotEmpty)
                          Text(place.location,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 10),
                        // Stop details row
                        _StopDetailsRow(
                          stop: stop,
                          nextStop: stopIndex < totalStops - 1
                              ? trip.tripStops![stopIndex + 1]
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Content ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Check In button (only for in-progress trips, not yet checked in) ──
                  if (trip.status == 'in_progress' && !checkedIn) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: checkingIn ? null : onCheckIn,
                        icon: checkingIn
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle),
                        label: Text(
                            checkingIn ? 'Checking in...' : 'Check In'),
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Map Section (always shown by default, toggle to hide) ──
                  if (place.latitude != null && place.longitude != null) ...[
                    Row(
                      children: [
                        Icon(Icons.map, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text('Location',
                            style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        TextButton(
                          onPressed: onToggleMap,
                          child: Text(showMap ? 'Hide Map' : 'Show Map'),
                        ),
                      ],
                    ),
                    if (showMap) ...[
                      _StopMapWidget(place: place),
                      const SizedBox(height: 16),
                    ],
                  ],

                  // ── Place Details (condensed) ──
                  if (place.description.isNotEmpty) ...[
                    Text(place.description,
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                  ],
                  if (place.address.isNotEmpty || place.city.isNotEmpty)
                    _CompactDetailRow(
                      icon: Icons.location_on,
                      text: [
                        place.address,
                        place.city,
                        place.state,
                        place.zipCode,
                      ].where((s) => s.isNotEmpty).join(', '),
                      onTap: place.latitude != null && place.longitude != null
                          ? () => launchUrl(
                              Uri.parse('https://www.google.com/maps/search/?api=1&query=${place.latitude},${place.longitude}'),
                              mode: LaunchMode.externalApplication,
                            )
                          : null,
                    ),
                  if (place.phone.isNotEmpty)
                    _CompactDetailRow(
                      icon: Icons.phone,
                      text: place.phone,
                      onTap: () => launchUrl(Uri.parse('tel:${place.phone}')),
                    ),
                  if (place.website.isNotEmpty)
                    _CompactDetailRow(
                      icon: Icons.language,
                      text: place.website.replaceAll('https://', '').replaceAll('http://', '').replaceAll(RegExp(r'/$'), ''),
                      onTap: () => launchUrl(Uri.parse(place.website)),
                    ),

                  // ── Drink Menu (always available for planning) ──
                  const SizedBox(height: 24),
                  _DrinkMenuSection(
                    place: place,
                    onSelectItem: (checkedIn && visitId != null)
                        ? (item) => drinksSectionKey.currentState?.addFromMenu(item)
                        : null,
                    showAiTools: false,
                  ),

                  // ── My Drinks (only after check-in during live trip) ──
                  if (checkedIn && visitId != null) ...[
                    const SizedBox(height: 12),
                    _DrinksSection(
                      key: drinksSectionKey,
                      tripId: tripId,
                      visitId: visitId!,
                      place: place,
                      placeType: place.placeType,
                      existingWines: (existingVisitData?['wines_tasted'] as List<dynamic>?) ?? [],
                    ),
                  ],

                  // ── AI Tools (after drinks) ──
                  if (checkedIn && visitId != null) ...[
                    const SizedBox(height: 12),
                    _SmartRecommendationsCard(
                      place: place,
                      onAddDrink: (item) => drinksSectionKey.currentState?.addFromMenu(item),
                      tripId: tripId,
                      visitId: visitId,
                      existingVisitData: existingVisitData,
                    ),
                    const SizedBox(height: 8),
                    _PairingsCard(
                      place: place,
                      tripId: tripId,
                      visitId: visitId,
                      existingVisitData: existingVisitData,
                    ),
                    const SizedBox(height: 8),
                    FlightBuilderButton(
                      place: place,
                      tripId: tripId,
                      visitId: visitId,
                      existingVisitData: existingVisitData,
                    ),
                  ],

                  // ── Rate Experience (only after check-in during live trip) ──
                  if (checkedIn && visitId != null) ...[
                    const SizedBox(height: 24),
                    _RateExperienceSection(
                      tripId: tripId,
                      visitId: visitId!,
                      existingRatings: existingVisitData,
                    ),
                  ],

                  // ── Stop Notes (only after check-in during live trip) ──
                  if (checkedIn && visitId != null) ...[
                    const SizedBox(height: 24),
                    _StopNotesSection(
                      tripId: tripId,
                      visitId: visitId!,
                      existingNotes: (existingVisitData?['notes'] as String?) ?? '',
                    ),
                  ],

                  // ── Activity Feed (shows what trip members are doing) ──
                  if (checkedIn)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: _ActivityFeedSection(tripId: tripId),
                    ),

                  const SizedBox(height: 60), // room for nav bar
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom Prev/Next Navigation ──
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
                blurRadius: 8,
                color: Colors.black.withValues(alpha: 0.1),
                offset: const Offset(0, -2)),
          ],
        ),
        child: Row(
          children: [
            if (stopIndex > 0)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onNavigate(stopIndex - 1),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Prev'),
                ),
              )
            else
              const Expanded(child: SizedBox()),
            const SizedBox(width: 8),
            if (stopIndex < totalStops - 1)
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onNavigate(stopIndex + 1),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next'),
                ),
              )
            else
              Expanded(
                child: trip.status == 'in_progress' && checkedIn
                    ? FilledButton.icon(
                        onPressed: onCompleteTrip,
                        icon: const Icon(Icons.celebration, size: 18),
                        label: const Text('Complete Trip'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green[700],
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => context.go('/trips/$tripId'),
                        icon: const Icon(Icons.flag),
                        label: const Text('Back to Trip'),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gradientBg(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, const Color(0xFF5DADE2)],
        ),
      ),
    );
  }
}

// ── Detail Tile ─────────────────────────────────────────────────

class _CompactDetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  const _CompactDetailRow({
    required this.icon,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    fontSize: 13,
                    color: onTap != null ? cs.primary : null,
                    decoration: onTap != null ? TextDecoration.underline : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  const _DetailTile(this.icon, this.text, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    color: onTap != null
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    decoration:
                        onTap != null ? TextDecoration.underline : null,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Drinks Section ──────────────────────────────────────────────

class _DrinksSection extends ConsumerStatefulWidget {
  final String tripId;
  final String visitId;
  final Place place;
  final List<dynamic> existingWines;
  final String placeType;
  const _DrinksSection({
    super.key,
    required this.tripId,
    required this.visitId,
    required this.place,
    required this.existingWines,
    required this.placeType,
  });

  @override
  ConsumerState<_DrinksSection> createState() => _DrinksSectionState();
}

class _DrinksSectionState extends ConsumerState<_DrinksSection> {
  late List<Map<String, dynamic>> _addedDrinks;

  List<Map<String, dynamic>> _parseWines(List<dynamic> wines) {
    // Build a lookup from menu item id → image_url for local fallback
    final menuImageMap = <String, String>{};
    for (final mi in (widget.place.menuItems ?? [])) {
      if (mi.imageUrl.isNotEmpty) menuImageMap[mi.id] = mi.imageUrl;
    }

    return wines.map((w) {
      final wine = w as Map<String, dynamic>;
      // Try API-provided image, then local menu item match
      final menuItemId = wine['menu_item'] as String? ?? '';
      final apiMenuImage = wine['menu_item_image_url'] as String? ?? '';
      final localMenuImage = menuImageMap[menuItemId] ?? '';
      final menuImage = apiMenuImage.isNotEmpty ? apiMenuImage : localMenuImage;

      return <String, dynamic>{
        'id': wine['id'] ?? '',
        'wine_name': wine['display_name'] ?? wine['wine_name'] ?? '',
        'wine_type': wine['wine_type'] ?? '',
        'wine_vintage': wine['wine_vintage'],
        'serving_type': wine['serving_type'] ?? '',
        'rating': wine['rating'],
        'tasting_notes': wine['tasting_notes'] ?? '',
        'rating_comments': wine['rating_comments'] ?? '',
        'is_favorite': wine['is_favorite'] ?? false,
        'purchased': wine['purchased'] ?? false,
        'purchased_price': wine['purchased_price'],
        'purchased_quantity': wine['purchased_quantity'],
        'photo': wine['photo'] ?? '',
        'menu_item_image': menuImage,
        'quantity': wine['quantity'] ?? 1,
      };
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _addedDrinks = _parseWines(widget.existingWines);
  }

  @override
  void didUpdateWidget(_DrinksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.existingWines != widget.existingWines) {
      setState(() => _addedDrinks = _parseWines(widget.existingWines));
    }
  }

  Future<void> _deleteDrink(int index) async {
    final drink = _addedDrinks[index];
    final drinkId = drink['id'] as String?;
    if (drinkId == null || drinkId.isEmpty) {
      setState(() => _addedDrinks.removeAt(index));
      return;
    }
    try {
      final api = ref.read(apiClientProvider);
      await api.delete('${ApiPaths.visits}${widget.visitId}/wines/$drinkId/');
      if (mounted) {
        setState(() => _addedDrinks.removeAt(index));
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

  Future<void> _editDrink(int index) async {
    final drink = Map<String, dynamic>.from(_addedDrinks[index]);
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
          placeType: widget.placeType,
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

        // Upload photo if one was picked
        String? photoUrl = result['photo'] as String?;
        if (pickedPhoto != null) {
          photoUrl = await _uploadPhoto(drinkId, pickedPhoto);
        }

        setState(() => _addedDrinks[index] = {
              ...result,
              'id': drinkId,
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

  Future<void> _addDrink() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _DrinkFormSheet(
          menuItems: widget.place.menuItems ?? [],
          placeType: widget.placeType,
          title: 'Add Drink',
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      final api = ref.read(apiClientProvider);
      final pickedPhoto = result.remove('_picked_photo') as XFile?;
      final resp = await api.post(
        '${ApiPaths.trips}${widget.tripId}/live/wine/',
        data: {...result, 'visit_id': widget.visitId},
      );
      final respData = resp.data['data'] as Map<String, dynamic>?;
      final drinkId = respData?['id'] as String? ?? '';

      // Upload photo if one was picked
      String? photoUrl;
      if (pickedPhoto != null && drinkId.isNotEmpty) {
        photoUrl = await _uploadPhoto(drinkId, pickedPhoto);
      }

      setState(() {
        _addedDrinks.add({
          ...result,
          'id': drinkId,
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

  Future<void> addFromMenu(Map<String, dynamic> menuItem) async {
    // Pre-fill the drink form with menu item data
    final prefill = <String, dynamic>{
      'wine_name': menuItem['name'] ?? '',
      'wine_type': menuItem['varietal'] ?? '',
      'tasting_notes': menuItem['description'] ?? '',
      'menu_item': menuItem['id'],
    };
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
          placeType: widget.placeType,
          title: 'Add ${menuItem['name']}',
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      final api = ref.read(apiClientProvider);
      final pickedPhoto = result.remove('_picked_photo') as XFile?;
      final resp = await api.post(
        '${ApiPaths.trips}${widget.tripId}/live/wine/',
        data: {
          ...result,
          'visit_id': widget.visitId,
          'menu_item': menuItem['id'],
        },
      );
      final respData = resp.data['data'] as Map<String, dynamic>?;
      final drinkId = respData?['id'] as String? ?? '';

      String? photoUrl;
      if (pickedPhoto != null && drinkId.isNotEmpty) {
        photoUrl = await _uploadPhoto(drinkId, pickedPhoto);
      }

      setState(() {
        _addedDrinks.add({
          ...result,
          'id': drinkId,
          if (photoUrl != null && photoUrl.isNotEmpty) 'photo': photoUrl,
          'menu_item_image': menuItem['image_url'] ?? '',
        });
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${menuItem['name']} added!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text('My Drinks (${_addedDrinks.length})',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              onPressed: _addDrink,
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add Drink',
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(_addedDrinks.length, (i) {
          return _DrinkCard(
            drink: _addedDrinks[i],
            onEdit: () => _editDrink(i),
            onDelete: () => _deleteDrink(i),
          );
        }),
        if (_addedDrinks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.local_drink, size: 40, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    const Text('No drinks logged yet'),
                    const Text('Tap "Add Drink" to get started',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Activity Feed Section ────────────────────────────────────────

class _ActivityFeedSection extends ConsumerStatefulWidget {
  final String tripId;
  const _ActivityFeedSection({required this.tripId});

  @override
  ConsumerState<_ActivityFeedSection> createState() => _ActivityFeedSectionState();
}

class _ActivityFeedSectionState extends ConsumerState<_ActivityFeedSection> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _fetchActivity();
  }

  Future<void> _fetchActivity() async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.get(ApiPaths.tripActivity(widget.tripId));
      final data = resp.data['data'] as Map<String, dynamic>? ?? resp.data as Map<String, dynamic>;
      final events = (data['events'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];
      if (mounted) setState(() { _events = events; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _eventText(Map<String, dynamic> event) {
    final user = event['user_name'] as String? ?? 'Someone';
    final type = event['type'] as String? ?? '';
    switch (type) {
      case 'checkin':
        final place = event['place_name'] as String? ?? 'a place';
        final rating = event['rating'];
        return rating != null
            ? '$user checked in at $place ($rating/5)'
            : '$user checked in at $place';
      case 'wine':
        final wine = event['wine_name'] as String? ?? 'a wine';
        final fav = event['is_favorite'] == true ? ' [fav]' : '';
        final rating = event['rating'];
        return rating != null
            ? '$user tasted $wine$fav ($rating/5)'
            : '$user tasted $wine$fav';
      case 'rating':
        final wine = event['wine_name'] as String? ?? 'a wine';
        return '$user rated $wine ${event['rating']}/5';
      default:
        return '$user did something';
    }
  }

  IconData _eventIcon(String type) {
    switch (type) {
      case 'checkin':
        return Icons.location_on;
      case 'wine':
        return Icons.wine_bar;
      case 'rating':
        return Icons.star;
      default:
        return Icons.notifications;
    }
  }

  Color _eventColor(String type) {
    switch (type) {
      case 'checkin':
        return Colors.green;
      case 'wine':
        return Colors.purple;
      case 'rating':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  String _timeAgo(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Column(
        children: [
          SizedBox(height: 8),
          Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        ],
      );
    }

    if (_events.isEmpty) return const SizedBox.shrink();

    final displayEvents = _expanded ? _events : _events.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text('Trip Activity', style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(
              onPressed: _fetchActivity,
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...displayEvents.map((event) {
          final type = event['type'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_eventIcon(type), size: 16, color: _eventColor(type)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _eventText(event),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  _timeAgo(event['timestamp'] as String? ?? ''),
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }),
        if (_events.length > 5)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Show less' : 'Show all (${_events.length})'),
          ),
      ],
    );
  }
}

// ── Drink Form Bottom Sheet (shared for Add & Edit) ─────────────

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
  /// Convert a lowercase_underscore value back to Title Case label.
  /// e.g. "half_pint" → "Half Pint", "tasting" → "Tasting"
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
    final photo = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (photo != null) {
      setState(() {
        _pickedPhoto = photo;
        _existingPhotoUrl = null;
      });
    }
  }

  Future<void> _scanLabel() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;

    setState(() {
      _scanning = true;
      _pickedPhoto = photo;
      _existingPhotoUrl = null;
    });

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
      final resp = await api.dio.post(
        ApiPaths.scanLabel,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      final data = resp.data is Map
          ? resp.data as Map<String, dynamic>
          : <String, dynamic>{};
      final nested = data['data'] as Map<String, dynamic>? ?? data;

      if (mounted) {
        final name = nested['name'] as String? ?? '';
        final varietal = nested['varietal'] as String? ?? '';
        final vintage = nested['vintage'] as String? ?? '';
        final description = nested['description'] as String? ?? '';

        setState(() {
          if (name.isNotEmpty) _nameCtl.text = name;
          if (varietal.isNotEmpty) _type = varietal;
          if (description.isNotEmpty) _notesCtl.text = description;
          _scanning = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(name.isNotEmpty
                ? 'Found: $name${vintage.isNotEmpty ? " ($vintage)" : ""}'
                : 'Could not read label clearly. Try again.'),
            backgroundColor: name.isNotEmpty ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
                        ? Image.network(
                            _pickedPhoto!.path,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            File(_pickedPhoto!.path),
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                    : Image.network(
                        _existingPhotoUrl!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 160,
                          color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.broken_image)),
                        ),
                      ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 14, color: Colors.white),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() {
                      _pickedPhoto = null;
                      _existingPhotoUrl = null;
                    }),
                  ),
                ),
              ),
            ],
          )
        else
          GestureDetector(
            onTap: () => _pickImage(ImageSource.camera),
            child: Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[50],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 32, color: Colors.grey[500]),
                  const SizedBox(height: 4),
                  Text('Add Photo', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drink name is required')),
      );
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
    const defaultServing = 'Tasting';
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
            // Handle bar
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // Scan Label button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _scanning ? null : _scanLabel,
                icon: _scanning
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner),
                label: Text(_scanning ? 'Scanning label...' : 'Scan Label with AI'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
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
                        if (item.varietal.isNotEmpty) {
                          setState(() => _type = item.varietal);
                        }
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 20),
            ],

            // Name
            TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(labelText: 'Drink Name'),
            ),
            const SizedBox(height: 12),

            // Type + Serving
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: typeOptions.contains(_type) ? _type : typeOptions.first,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: typeOptions
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: servingOptions.contains(_serving) ? _serving : servingOptions.first,
                    decoration: const InputDecoration(labelText: 'Serving'),
                    items: servingOptions
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _serving = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tasting notes
            TextField(
              controller: _notesCtl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Tasting Notes'),
            ),
            const SizedBox(height: 12),

            // Photo
            _buildPhotoSection(),
            const SizedBox(height: 12),

            // Rating comments
            TextField(
              controller: _ratingCommentsCtl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Rating Comments',
                hintText: 'What did you like or dislike?',
              ),
            ),
            const SizedBox(height: 12),

            // Rating
            Row(
              children: [
                const Text('Rating: '),
                RatingStars(
                  rating: _rating,
                  size: 28,
                  onChanged: (v) => setState(() => _rating = v),
                ),
                if (_rating != null) ...[
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _rating = null),
                    child: const Text('Clear', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Favorite toggle
            SwitchListTile(
              title: const Text('Favorite'),
              secondary: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? Colors.red : null,
              ),
              value: _isFavorite,
              onChanged: (v) => setState(() => _isFavorite = v),
              contentPadding: EdgeInsets.zero,
            ),

            // Wishlist / Want to Try
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
                  await api.post(ApiPaths.wishlist, data: {
                    'wine_name': _nameCtl.text,
                    'wine_type': _type,
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${_nameCtl.text} added to wishlist!'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not add to wishlist')),
                    );
                  }
                }
              },
            ),

            // Purchased toggle + details
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
                    child: TextField(
                      controller: _priceCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        prefixText: '\$',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _purchasedQty ?? 1,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      items: List.generate(12, (i) => i + 1)
                          .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                          .toList(),
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


// ── Rate Experience Section ─────────────────────────────────────

class _RateExperienceSection extends ConsumerStatefulWidget {
  final String tripId;
  final String visitId;
  final Map<String, dynamic>? existingRatings;
  const _RateExperienceSection({
    required this.tripId,
    required this.visitId,
    this.existingRatings,
  });

  @override
  ConsumerState<_RateExperienceSection> createState() =>
      _RateExperienceSectionState();
}

class _RateExperienceSectionState
    extends ConsumerState<_RateExperienceSection> {
  late int? _overall;
  late int? _staff;
  late int? _ambience;
  late int? _food;
  late bool _saved;
  bool _saving = false;
  bool _dirty = false; // true when user changed a rating

  @override
  void initState() {
    super.initState();
    _loadFromExisting();
  }

  @override
  void didUpdateWidget(covariant _RateExperienceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If parent passes new existing data (e.g. after re-fetch), reload
    // but only if user hasn't made unsaved changes
    if (!_dirty && widget.existingRatings != oldWidget.existingRatings) {
      _loadFromExisting();
    }
  }

  void _loadFromExisting() {
    final r = widget.existingRatings;
    _overall = r?['rating_overall'] as int?;
    _staff = r?['rating_staff'] as int?;
    _ambience = r?['rating_ambience'] as int?;
    _food = r?['rating_food'] as int?;
    _saved = (_overall != null || _staff != null || _ambience != null || _food != null);
    _dirty = false;
  }

  void _setRating(void Function() update) {
    setState(() {
      update();
      _dirty = true;
      _saved = false; // user changed something — needs to re-save
    });
  }

  Future<void> _resetRatings() async {
    setState(() {
      _overall = null;
      _staff = null;
      _ambience = null;
      _food = null;
      _dirty = true;
      _saved = false;
    });
    // Save the reset to the server
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        '${ApiPaths.trips}${widget.tripId}/live/rate/${widget.visitId}/',
        data: {
          'rating_overall': null,
          'rating_staff': null,
          'rating_ambience': null,
          'rating_food': null,
        },
      );
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Ratings cleared'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        '${ApiPaths.trips}${widget.tripId}/live/rate/${widget.visitId}/',
        data: {
          'rating_overall': _overall,
          'rating_staff': _staff,
          'rating_ambience': _ambience,
          'rating_food': _food,
        },
      );
      if (mounted) {
        setState(() {
          _saved = true;
          _saving = false;
          _dirty = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rating saved!'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[RateExperience] FAILED: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rate Experience',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _RatingRow('Overall', _overall,
                    (v) => _setRating(() => _overall = v)),
                _RatingRow(
                    'Staff', _staff, (v) => _setRating(() => _staff = v)),
                _RatingRow('Ambience', _ambience,
                    (v) => _setRating(() => _ambience = v)),
                _RatingRow('Food & Drinks', _food,
                    (v) => _setRating(() => _food = v)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _saved && !_dirty
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle,
                                    color: Colors.green, size: 20),
                                const SizedBox(width: 8),
                                Text('Rating saved',
                                    style: TextStyle(color: Colors.green[700])),
                              ],
                            )
                          : FilledButton(
                              onPressed: _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Text('Save Rating'),
                            ),
                    ),
                    if (_overall != null || _staff != null || _ambience != null || _food != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => _resetRatings(),
                        child: const Text('Reset',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String label;
  final int? rating;
  final ValueChanged<int> onChanged;
  const _RatingRow(this.label, this.rating, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          RatingStars(rating: rating, size: 28, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ── Drink Menu Section (always visible, for planning) ───────────

class _DrinkMenuSection extends ConsumerStatefulWidget {
  final Place place;
  final ValueChanged<Map<String, dynamic>>? onSelectItem;
  final bool showAiTools;
  final String? tripId;
  final String? visitId;
  final Map<String, dynamic>? existingVisitData;
  const _DrinkMenuSection({
    required this.place,
    this.onSelectItem,
    this.showAiTools = false,
    this.tripId,
    this.visitId,
    this.existingVisitData,
  });

  @override
  ConsumerState<_DrinkMenuSection> createState() => _DrinkMenuSectionState();
}

class _DrinkMenuSectionState extends ConsumerState<_DrinkMenuSection> {
  List<Map<String, dynamic>>? _menuItems;
  bool _fetching = false;
  bool _expanded = true;
  Set<String> _wishlistedNames = {};

  @override
  void initState() {
    super.initState();
    _loadExistingMenu();
    _loadWishlistMatches();
  }

  @override
  void didUpdateWidget(_DrinkMenuSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.id != widget.place.id) {
      _menuItems = null;
      _wishlistedNames = {};
      _loadExistingMenu();
      _loadWishlistMatches();
    }
  }

  Future<void> _loadWishlistMatches() async {
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

  Future<void> _loadExistingMenu() async {
    // Check if menu items already exist in DB for this place
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
      }
    } catch (_) {}
  }

  Future<void> _fetchFromWebsite() async {
    setState(() => _fetching = true);
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
        _fetching = false;
        _expanded = true;
      });
      if (items.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No menu items found on website')),
        );
      }
    } catch (e) {
      setState(() => _fetching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching menu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: Colors.amber),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _menuItems != null
                    ? 'Drink Menu (${_menuItems!.length})'
                    : 'Drink Menu',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_menuItems != null && _menuItems!.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Hide' : 'Show',
                    style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Fetch menu button
        if ((_menuItems == null || _menuItems!.isEmpty) &&
            widget.place.website.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _fetching ? null : _fetchFromWebsite,
              icon: _fetching
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 16),
              label: Text(_fetching ? 'Scanning website...' : 'Fetch Menu from Website',
                  style: const TextStyle(fontSize: 12)),
            ),
          )
        else if ((_menuItems == null || _menuItems!.isEmpty) &&
            widget.place.website.isEmpty)
          const Text('No menu available',
              style: TextStyle(color: Colors.grey, fontSize: 13))
        else if (_fetching)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Refreshing menu...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),

        // Menu items carousel
        if (_expanded && _menuItems != null && _menuItems!.isNotEmpty) ...[
          SizedBox(
            height: 140,
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
                  return _MenuItemCard(
                    item: item,
                    initialWishlisted: _wishlistedNames.contains(itemName),
                    onSelect: () {
                      widget.onSelectItem?.call(item);
                    },
                  );
                },
              ),
            ),
          ),
          // Refresh button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _fetching ? null : _fetchFromWebsite,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('Refresh', style: TextStyle(fontSize: 12)),
            ),
          ),

        ],
      ],
    );
  }
}

class _DrinkCard extends StatefulWidget {
  final Map<String, dynamic> drink;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _DrinkCard({
    required this.drink,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_DrinkCard> createState() => _DrinkCardState();
}

class _DrinkCardState extends State<_DrinkCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animController;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  String _resolveImageUrl(String url) {
    if (url.isEmpty) return url;
    if (!kIsWeb) return url;
    if (url.contains('vinoshipper') || url.contains('s3.amazonaws')) {
      return '${EnvConfig.apiBaseUrl}/api/v1/image-proxy/?url=${Uri.encodeComponent(url)}';
    }
    return url;
  }

  void _showFullImage(String imageUrl) {
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
                child: Image.network(
                  _resolveImageUrl(imageUrl),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
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
    final d = widget.drink;
    final cs = Theme.of(context).colorScheme;
    final name = d['wine_name'] as String? ?? '';
    final type = d['wine_type'] as String? ?? '';
    final vintage = d['wine_vintage'];
    final serving = d['serving_type'] as String? ?? '';
    final rating = d['rating'] as int?;
    final notes = d['tasting_notes'] as String? ?? '';
    final ratingComments = d['rating_comments'] as String? ?? '';
    final isFavorite = d['is_favorite'] as bool? ?? false;
    final purchased = d['purchased'] as bool? ?? false;
    final price = d['purchased_price'];
    final qty = d['purchased_quantity'];
    final quantity = (d['quantity'] as int?) ?? 1;

    // Resolve drink image: user photo > menu item image
    final photo = d['photo'] as String? ?? '';
    final menuItemImage = d['menu_item_image'] as String? ?? '';
    final drinkImage = photo.isNotEmpty ? photo : menuItemImage;
    final hasImage = drinkImage.isNotEmpty;
    final resolvedImage = hasImage ? _resolveImageUrl(drinkImage) : '';

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: _expanded ? 3 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero image or gradient header ──
          GestureDetector(
            onTap: hasImage ? () => _showFullImage(drinkImage) : _toggleExpand,
            child: Stack(
              children: [
                // Image / gradient background
                SizedBox(
                  height: hasImage ? 140 : 72,
                  width: double.infinity,
                  child: hasImage
                      ? Image.network(
                          resolvedImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _gradientHeader(cs),
                        )
                      : _gradientHeader(cs),
                ),
                // Dark gradient overlay for readability
                if (hasImage)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: const [0.3, 1.0],
                        ),
                      ),
                    ),
                  ),
                // Badge row: favorite + purchased
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isFavorite)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.favorite,
                              color: Colors.redAccent, size: 16),
                        ),
                      if (isFavorite && purchased) const SizedBox(width: 6),
                      if (purchased)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.shopping_bag,
                                  color: Colors.white, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                [
                                  if (qty != null) '${qty}x',
                                  if (price != null) '\$$price',
                                  if (qty == null && price == null) 'Bought',
                                ].join(' '),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Quantity badge top-left
                if (quantity > 1)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text('x$quantity',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                // Wine name + type overlay at bottom
                Positioned(
                  left: 12,
                  right: 60,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: hasImage ? Colors.white : cs.onPrimaryContainer,
                          shadows: hasImage
                              ? [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                  )
                                ]
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [type, if (vintage != null) '$vintage', serving]
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: hasImage
                              ? Colors.white70
                              : cs.onPrimaryContainer.withValues(alpha: 0.7),
                          shadows: hasImage
                              ? [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                  )
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                // Rating badge bottom-right
                if (rating != null)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _ratingColor(rating),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 2),
                          Text(
                            '$rating',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Info strip with expand toggle ──
          InkWell(
            onTap: _toggleExpand,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Quick-info chips
                  if (notes.isNotEmpty)
                    _infoChip(Icons.notes, 'Notes', cs),
                  if (notes.isNotEmpty && ratingComments.isNotEmpty)
                    const SizedBox(width: 6),
                  if (ratingComments.isNotEmpty)
                    _infoChip(Icons.rate_review_outlined, 'Review', cs),
                  const Spacer(),
                  // Edit / Delete quick-actions
                  _iconAction(Icons.edit_outlined, cs.primary, widget.onEdit),
                  const SizedBox(width: 4),
                  _iconAction(Icons.delete_outline, cs.error, widget.onDelete),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(Icons.expand_more,
                        color: Colors.grey.shade500, size: 22),
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable detail section ──
          SizeTransition(
            sizeFactor: _expandAnim,
            axisAlignment: -1.0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Rating stars full display
                  if (rating != null) ...[
                    Row(
                      children: [
                        RatingStars(rating: rating, size: 22),
                        const SizedBox(width: 8),
                        Text('$rating / 5',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _ratingColor(rating))),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Tasting notes
                  if (notes.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.notes, size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Text('Tasting Notes',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.primary)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(notes,
                          style: const TextStyle(
                              fontSize: 13, height: 1.4)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Rating comments
                  if (ratingComments.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.rate_review_outlined,
                            size: 14, color: cs.secondary),
                        const SizedBox(width: 6),
                        Text('Review',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.secondary)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(ratingComments,
                          style: const TextStyle(
                              fontSize: 13, height: 1.4)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Favorite & Purchase detail row
                  Row(
                    children: [
                      _detailBadge(
                        icon: isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        label: isFavorite ? 'Favorited' : 'Not favorited',
                        color: isFavorite ? Colors.redAccent : Colors.grey,
                        filled: isFavorite,
                      ),
                      const SizedBox(width: 8),
                      _detailBadge(
                        icon: purchased
                            ? Icons.shopping_bag
                            : Icons.shopping_bag_outlined,
                        label: purchased
                            ? [
                                'Purchased',
                                if (qty != null) '(${qty}x)',
                                if (price != null) '\$$price',
                              ].join(' ')
                            : 'Not purchased',
                        color: purchased
                            ? Colors.green.shade600
                            : Colors.grey,
                        filled: purchased,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Gradient header when there's no image
  Widget _gradientHeader(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer,
            cs.secondaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.wine_bar_rounded,
            size: 32, color: cs.onPrimaryContainer.withValues(alpha: 0.4)),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _iconAction(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
      ),
    );
  }

  Widget _detailBadge({
    required IconData icon,
    required String label,
    required Color color,
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: color.withValues(alpha: filled ? 0.3 : 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight:
                        filled ? FontWeight.w600 : FontWeight.normal),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Color _ratingColor(int rating) {
    if (rating >= 5) return const Color(0xFF27AE60);
    if (rating >= 4) return const Color(0xFF2ECC71);
    if (rating >= 3) return const Color(0xFFF39C12);
    if (rating >= 2) return const Color(0xFFE67E22);
    return const Color(0xFFE74C3C);
  }
}

// ── Stop Notes Section ──────────────────────────────────────────

class _StopNotesSection extends ConsumerStatefulWidget {
  final String tripId;
  final String visitId;
  final String existingNotes;
  const _StopNotesSection({
    required this.tripId,
    required this.visitId,
    required this.existingNotes,
  });

  @override
  ConsumerState<_StopNotesSection> createState() => _StopNotesSectionState();
}

class _StopNotesSectionState extends ConsumerState<_StopNotesSection> {
  late final TextEditingController _notesCtl;
  bool _saved = false;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _notesCtl = TextEditingController(text: widget.existingNotes);
    _saved = widget.existingNotes.isNotEmpty;
    _notesCtl.addListener(() {
      if (!_dirty && _notesCtl.text != widget.existingNotes) {
        setState(() {
          _dirty = true;
          _saved = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        '${ApiPaths.trips}${widget.tripId}/live/rate/${widget.visitId}/',
        data: {'notes': _notesCtl.text},
      );
      if (mounted) {
        setState(() {
          _saved = true;
          _saving = false;
          _dirty = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notes saved!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stop Notes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _notesCtl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Share your thoughts about this place...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _saved && !_dirty
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Text('Notes saved',
                                style: TextStyle(color: Colors.green[700])),
                          ],
                        )
                      : FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Save Notes'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Stop Map Widget ─────────────────────────────────────────────

// ── Header Helper Widgets ────────────────────────────────────────

class _CheckedInBadge extends StatelessWidget {
  const _CheckedInBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.white, size: 16),
          SizedBox(width: 4),
          Text('Checked In',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;
  final bool filled;
  final Color? color;
  final Color? textColor;
  const _HeaderChip(this.label,
      {this.filled = false, this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? (color ?? Colors.white) : Colors.black45,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              color: filled ? (textColor ?? Colors.black) : Colors.white,
              fontSize: filled ? 12 : 10,
              fontWeight: FontWeight.bold)),
    );
  }
}

class _StopDetailsRow extends StatelessWidget {
  final TripStop stop;
  final TripStop? nextStop;
  const _StopDetailsRow({required this.stop, this.nextStop});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Arrival Date, Time, Duration
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (stop.arrivalTime != null)
              _DetailPill(Icons.calendar_today, _formatDate(stop.arrivalTime!)),
            if (stop.arrivalTime != null)
              _DetailPill(Icons.schedule, _formatTime(stop.arrivalTime!)),
            if (stop.durationMinutes != null)
              _DetailPill(Icons.timer, '${stop.durationMinutes} min'),
          ],
        ),
        // Row 2: Drive Time and Distance
        if (nextStop != null &&
            (nextStop!.travelMinutes != null || nextStop!.travelMiles != null))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 12,
              children: [
                if (nextStop!.travelMinutes != null)
                  _DetailPill(Icons.directions_car,
                      '${nextStop!.travelMinutes} min to next'),
                if (nextStop!.travelMiles != null)
                  _DetailPill(Icons.straighten,
                      '${nextStop!.travelMiles!.toStringAsFixed(1)} mi'),
              ],
            ),
          ),
        if (nextStop == null && stop.order > 0)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: _DetailPill(Icons.flag, 'Last stop'),
          ),
      ],
    );
  }

  String _formatDate(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  String _formatTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:${dt.minute.toString().padLeft(2, '0')} $amPm';
    } catch (_) {
      return isoTime;
    }
  }
}

class _DetailPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DetailPill(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Edit Stop Sheet ─────────────────────────────────────────────

class _EditStopSheet extends ConsumerStatefulWidget {
  final String tripId;
  final TripStop stop;
  final TripStop? nextStop;
  const _EditStopSheet({
    required this.tripId,
    required this.stop,
    this.nextStop,
  });

  @override
  ConsumerState<_EditStopSheet> createState() => _EditStopSheetState();
}

class _EditStopSheetState extends ConsumerState<_EditStopSheet> {
  late final TextEditingController _durationCtl;
  late final TextEditingController _driveCtl;
  late final TextEditingController _milesCtl;
  late final TextEditingController _descCtl;
  late final TextEditingController _notesCtl;
  DateTime? _arrivalDate;
  TimeOfDay? _arrivalTime;
  bool _saving = false;
  bool _calculating = false;

  @override
  void initState() {
    super.initState();
    final s = widget.stop;
    // Parse existing arrival time
    if (s.arrivalTime != null && s.arrivalTime!.isNotEmpty) {
      try {
        final dt = DateTime.parse(s.arrivalTime!);
        _arrivalDate = DateTime(dt.year, dt.month, dt.day);
        _arrivalTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } catch (_) {}
    }
    _durationCtl = TextEditingController(
        text: s.durationMinutes != null ? '${s.durationMinutes}' : '60');
    _driveCtl = TextEditingController(
        text: s.travelMinutes != null ? '${s.travelMinutes}' : '');
    _milesCtl = TextEditingController(
        text: s.travelMiles != null ? '${s.travelMiles}' : '');
    _descCtl = TextEditingController(text: s.description);
    _notesCtl = TextEditingController(text: s.notes);
  }

  @override
  void dispose() {
    _durationCtl.dispose();
    _driveCtl.dispose();
    _milesCtl.dispose();
    _descCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  String? _buildArrivalIso() {
    if (_arrivalDate == null) return null;
    final d = _arrivalDate!;
    final t = _arrivalTime ?? const TimeOfDay(hour: 12, minute: 0);
    return DateTime(d.year, d.month, d.day, t.hour, t.minute).toIso8601String();
  }

  String _formatDate(DateTime d) => DateFormat('MM/dd/yyyy').format(d);
  String _formatTime(TimeOfDay t, BuildContext ctx) => t.format(ctx);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final arrivalIso = _buildArrivalIso();
      await api.patch(
        '${ApiPaths.trips}${widget.tripId}/stops/${widget.stop.id}/',
        data: {
          'duration_minutes': int.tryParse(_durationCtl.text),
          'travel_minutes': int.tryParse(_driveCtl.text),
          'travel_miles': double.tryParse(_milesCtl.text),
          'description': _descCtl.text,
          'notes': _notesCtl.text,
          if (arrivalIso != null) 'arrival_time': arrivalIso,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Stop updated'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2)),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _calculateDistance() async {
    final nextPlace = widget.nextStop?.place;
    if (nextPlace == null ||
        widget.stop.place?.latitude == null ||
        nextPlace.latitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Need coordinates for both stops')),
      );
      return;
    }

    setState(() => _calculating = true);
    try {
      final origin =
          '${widget.stop.place!.latitude},${widget.stop.place!.longitude}';
      final destination = '${nextPlace.latitude},${nextPlace.longitude}';

      final api = ref.read(apiClientProvider);
      final resp = await api.get(
        '/api/v1/distance-matrix/',
        queryParameters: {
          'origins': origin,
          'destinations': destination,
        },
      );
      final respData = resp.data['data'] as Map<String, dynamic>;
      final driveMin = respData['drive_minutes'] as int;
      final miles = (respData['miles'] as num).toDouble();

      setState(() {
        _driveCtl.text = '$driveMin';
        _milesCtl.text = miles.toStringAsFixed(1);
        _calculating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$driveMin min drive, ${miles.toStringAsFixed(1)} miles to ${nextPlace.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() => _calculating = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasNext = widget.nextStop != null;

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
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Text('Edit Stop', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.stop.place?.name ?? '',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),

            // Arrival Date & Time
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Arrival Date', style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      _arrivalDate != null
                          ? _formatDate(_arrivalDate!)
                          : 'Not set',
                      style: TextStyle(
                        fontSize: 13,
                        color: _arrivalDate != null ? null : Colors.grey,
                      ),
                    ),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _arrivalDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setState(() => _arrivalDate = d);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time),
                    title: const Text('Arrival Time', style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      _arrivalTime != null
                          ? _formatTime(_arrivalTime!, context)
                          : 'Not set',
                      style: TextStyle(
                        fontSize: 13,
                        color: _arrivalTime != null ? null : Colors.grey,
                      ),
                    ),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _arrivalTime ?? const TimeOfDay(hour: 12, minute: 0),
                      );
                      if (t != null) setState(() => _arrivalTime = t);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Duration
            TextField(
              controller: _durationCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes)',
                prefixIcon: Icon(Icons.timer),
              ),
            ),
            const SizedBox(height: 12),

            // Drive time & distance
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _driveCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Drive Time (min)',
                      prefixIcon: Icon(Icons.directions_car),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _milesCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Distance (miles)',
                      prefixIcon: Icon(Icons.straighten),
                    ),
                  ),
                ),
              ],
            ),

            // Calculate distance button
            if (hasNext)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _calculating ? null : _calculateDistance,
                    icon: _calculating
                        ? const SizedBox(
                            height: 16, width: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.route, size: 18),
                    label: Text(_calculating
                        ? 'Calculating...'
                        : 'Calculate Drive to ${widget.nextStop!.place?.name ?? "Next Stop"}'),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Description
            TextField(
              controller: _descCtl,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.description),
              ),
            ),
            const SizedBox(height: 12),

            // Notes
            TextField(
              controller: _notesCtl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _StopMapWidget extends StatefulWidget {
  final Place place;
  const _StopMapWidget({required this.place});

  @override
  State<_StopMapWidget> createState() => _StopMapWidgetState();
}

class _StopMapWidgetState extends State<_StopMapWidget> {
  GoogleMapController? _mapController;

  LatLng get _position => LatLng(widget.place.latitude!, widget.place.longitude!);

  @override
  void didUpdateWidget(_StopMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.id != widget.place.id) {
      _moveToPlace();
    }
  }

  void _moveToPlace() {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_position, 15),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 200,
        child: GoogleMap(
          key: ValueKey(widget.place.id),
          initialCameraPosition: CameraPosition(
            target: _position,
            zoom: 15,
          ),
          onMapCreated: (controller) {
            _mapController = controller;
          },
          markers: {
            Marker(
              markerId: MarkerId(widget.place.id),
              position: _position,
              infoWindow: InfoWindow(
                title: widget.place.name,
                snippet: widget.place.location,
              ),
            ),
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
        ),
      ),
    );
  }
}

// ── Menu Item Card (from website scrape) ────────────────────────

class _MenuItemCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onSelect;
  final bool initialWishlisted;
  const _MenuItemCard({required this.item, required this.onSelect, this.initialWishlisted = false});

  @override
  ConsumerState<_MenuItemCard> createState() => _MenuItemCardState();
}

class _MenuItemCardState extends ConsumerState<_MenuItemCard> {
  late bool _wishlisted = widget.initialWishlisted;

  Map<String, dynamic> get item => widget.item;
  VoidCallback get onSelect => widget.onSelect;

  Future<void> _toggleWishlist() async {
    final name = item['name'] as String? ?? '';
    if (name.isEmpty) return;
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post('${ApiPaths.wishlist}toggle/', data: {
        'wine_name': name,
        'wine_type': item['varietal'] as String? ?? '',
        'menu_item': item['id'],
      });
      final data = resp.data['data'] as Map<String, dynamic>? ??
          resp.data as Map<String, dynamic>;
      if (mounted) {
        setState(() => _wishlisted = data['wishlisted'] as bool? ?? !_wishlisted);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_wishlisted ? '$name added to wishlist!' : '$name removed from wishlist'),
            backgroundColor: _wishlisted ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  /// On web, third-party image URLs fail due to CORS.
  /// Only show images from our own domain or known CORS-friendly hosts.
  /// On web, proxy external images through our backend to avoid CORS.
  String? _getImageUrl(String url) {
    if (url.isEmpty) return null;
    if (!kIsWeb) return url;
    // Proxy through our backend to bypass CORS
    final encoded = Uri.encodeComponent(url);
    return '${EnvConfig.apiBaseUrl}/api/v1/image-proxy/?url=$encoded';
  }

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? '';
    final varietal = item['varietal'] as String? ?? '';
    final vintage = item['vintage'];
    final price = item['price'];
    final rawImageUrl = item['image_url'] as String? ?? '';
    final cs = Theme.of(context).colorScheme;
    final imageUrl = _getImageUrl(rawImageUrl);

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with wishlist button overlay
            Stack(
              children: [
                SizedBox(
                  height: 70,
                  width: double.infinity,
                  child: imageUrl != null
                      ? Image.network(imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(cs))
                      : _placeholder(cs),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: _toggleWishlist,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _wishlisted ? Icons.bookmark : Icons.bookmark_add_outlined,
                        size: 14,
                        color: _wishlisted ? cs.secondary : Colors.grey[600],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Details
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (varietal.isNotEmpty)
                      Text(
                        [varietal, if (vintage != null) '$vintage'].join(' '),
                        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (price != null)
                      Text('\$$price',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: cs.primary)),
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
// SMART RECOMMENDATIONS CARD
// ═══════════════════════════════════════════════════════════════════

class _SmartRecommendationsCard extends ConsumerStatefulWidget {
  final Place place;
  final ValueChanged<Map<String, dynamic>>? onAddDrink;
  final String? tripId;
  final String? visitId;
  final Map<String, dynamic>? existingVisitData;
  const _SmartRecommendationsCard({
    required this.place,
    this.onAddDrink,
    this.tripId,
    this.visitId,
    this.existingVisitData,
  });

  @override
  ConsumerState<_SmartRecommendationsCard> createState() =>
      _SmartRecommendationsCardState();
}

class _SmartRecommendationsCardState
    extends ConsumerState<_SmartRecommendationsCard> {
  List<Map<String, dynamic>>? _recommendations;
  bool _loading = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void didUpdateWidget(_SmartRecommendationsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.id != widget.place.id) {
      _recommendations = null;
      _dismissed = false;
      _loading = false;
      _loadSaved();
    }
  }

  void _loadSaved() {
    final meta = widget.existingVisitData?['metadata'] as Map<String, dynamic>?;
    if (meta != null && meta['recommendations'] is List) {
      final saved = (meta['recommendations'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      if (saved.isNotEmpty) {
        setState(() => _recommendations = saved);
      }
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post(ApiPaths.placeRecommend(widget.place.id));
      final data = resp.data['data'] as Map<String, dynamic>? ??
          resp.data as Map<String, dynamic>;
      final recs = (data['recommendations'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [];
      if (mounted) {
        setState(() { _recommendations = recs; _loading = false; });
        _save(recs);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(List<Map<String, dynamic>> recs) async {
    if (widget.tripId == null || widget.visitId == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        ApiPaths.liveMetadata(widget.tripId!, widget.visitId!),
        data: {'recommendations': recs},
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Removed _dismissed — closing clears data and shows button again
    final colorScheme = Theme.of(context).colorScheme;

    // Show button if no recommendations yet
    if (_recommendations == null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _loading ? null : _fetch,
          icon: _loading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome, size: 16),
          label: Text(_loading ? 'Getting recommendations...' : 'Get Recommendations',
              style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10),
            side: BorderSide(color: colorScheme.secondary),
          ),
        ),
      );
    }

    if (_recommendations!.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.secondary.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: colorScheme.secondary),
                const SizedBox(width: 6),
                Text('Recommended for You',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.secondary)),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() => _recommendations = null);
                    _save([]);
                  },
                  icon: const Icon(Icons.close, size: 16),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._recommendations!.map((rec) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onAddDrink != null
                        ? () {
                            widget.onAddDrink!({
                              'id': rec['menu_item_id'],
                              'name': rec['name'],
                            });
                          }
                        : null,
                    child: Row(
                      children: [
                        Icon(Icons.wine_bar, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rec['name'] as String? ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(rec['why'] as String? ?? '',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                        if (widget.onAddDrink != null)
                          Icon(Icons.add_circle_outline, size: 18, color: colorScheme.primary),
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// WINE & FOOD PAIRINGS CARD
// ═══════════════════════════════════════════════════════════════════

class _PairingsCard extends ConsumerStatefulWidget {
  final Place place;
  final String? tripId;
  final String? visitId;
  final Map<String, dynamic>? existingVisitData;
  const _PairingsCard({required this.place, this.tripId, this.visitId, this.existingVisitData});

  @override
  ConsumerState<_PairingsCard> createState() => _PairingsCardState();
}

class _PairingsCardState extends ConsumerState<_PairingsCard> {
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _dismissed = false;

  @override
  void didUpdateWidget(_PairingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.id != widget.place.id) {
      _data = null;
      _dismissed = false;
      _loading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  void _loadSaved() {
    final meta = widget.existingVisitData?['metadata'] as Map<String, dynamic>?;
    if (meta != null && meta['pairings'] is Map) {
      final saved = meta['pairings'] as Map<String, dynamic>;
      if (saved.isNotEmpty && (saved['pairings'] as List?)?.isNotEmpty == true) {
        setState(() => _data = saved);
      }
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post(ApiPaths.placePairings(widget.place.id));
      final data = resp.data['data'] as Map<String, dynamic>? ??
          resp.data as Map<String, dynamic>;
      if (mounted) {
        setState(() { _data = data; _loading = false; });
        _save(data);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed: $e'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  Future<void> _save(Map<String, dynamic> pairingData) async {
    if (widget.tripId == null || widget.visitId == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        ApiPaths.liveMetadata(widget.tripId!, widget.visitId!),
        data: {'pairings': pairingData},
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Removed _dismissed — closing clears data and shows button again
    final colorScheme = Theme.of(context).colorScheme;
    final isWinery = widget.place.placeType == 'winery' || widget.place.placeType == 'brewery';
    final label = isWinery ? 'Food Pairings' : 'Wine Pairings';

    if (_data == null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _loading ? null : _fetch,
          icon: _loading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.restaurant_menu, size: 16),
          label: Text(_loading ? 'Finding pairings...' : 'Get $label',
              style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10),
            side: BorderSide(color: colorScheme.tertiary),
          ),
        ),
      );
    }

    final pairings = (_data!['pairings'] as List?) ?? [];
    final generalTip = _data!['general_tip'] as String? ?? '';

    if (pairings.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.tertiary.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant_menu, size: 16, color: colorScheme.tertiary),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.tertiary)),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() => _data = null);
                    _save({});
                  },
                  icon: const Icon(Icons.close, size: 16),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            if (generalTip.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(generalTip, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 8),
            ...pairings.map((p) {
              final pairing = p as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(isWinery ? Icons.lunch_dining : Icons.wine_bar,
                        size: 14, color: colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
                              children: [
                                TextSpan(text: '${pairing['item']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                TextSpan(text: ' + ${pairing['pairs_with']}'),
                              ],
                            ),
                          ),
                          Text(pairing['why'] as String? ?? '',
                              style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                          if ((pairing['tip'] as String? ?? '').isNotEmpty)
                            Text(pairing['tip'] as String,
                                style: TextStyle(fontSize: 10, color: colorScheme.tertiary, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
