import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/trip.dart';

class TripStopDrawer extends StatelessWidget {
  final Trip trip;
  final int? currentStopIndex;
  final ValueChanged<int>? onNavigate;
  final String tripId;

  /// Trip-level actions (shown when at trip detail level)
  final VoidCallback? onEditTrip;
  final VoidCallback? onDeleteTrip;

  /// Show full route map
  final VoidCallback? onShowRoute;

  /// Stop-level actions (shown when at stop detail level)
  final VoidCallback? onEditStop;
  final VoidCallback? onDeleteStop;

  const TripStopDrawer({
    super.key,
    required this.trip,
    this.currentStopIndex,
    this.onNavigate,
    required this.tripId,
    this.onEditTrip,
    this.onDeleteTrip,
    this.onShowRoute,
    this.onEditStop,
    this.onDeleteStop,
  });

  /// Are we viewing from within a stop detail?
  bool get _isStopLevel => currentStopIndex != null;

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

  IconData _placeTypeIcon(String? type) {
    switch (type) {
      case 'winery':
        return Icons.wine_bar;
      case 'brewery':
        return Icons.sports_bar;
      case 'restaurant':
        return Icons.restaurant;
      default:
        return Icons.place;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stops = trip.tripStops ?? [];
    final currentPlace = _isStopLevel && currentStopIndex! < stops.length
        ? stops[currentStopIndex!].place
        : null;

    final bool hasEditDelete = onEditTrip != null ||
        onDeleteTrip != null ||
        onEditStop != null ||
        onDeleteStop != null;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.78,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ═══ Trip Header ═══
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(color: colorScheme.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          trip.status.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${stops.length} stops',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ═══ 1) Trip Details ═══
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text('TRIP DETAILS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[500],
                      letterSpacing: 1)),
            ),
            if (_isStopLevel)
              ListTile(
                dense: true,
                leading:
                    Icon(Icons.map, color: colorScheme.primary, size: 20),
                title: const Text('Trip Overview',
                    style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/trips/$tripId');
                },
              ),
            if (trip.status == 'completed')
              ListTile(
                dense: true,
                leading: const Icon(Icons.auto_stories,
                    color: Color(0xFF8E44AD), size: 20),
                title:
                    const Text('Trip Recap', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/trips/$tripId/recap');
                },
              ),
            if (onShowRoute != null && (trip.tripStops?.length ?? 0) > 1)
              ListTile(
                dense: true,
                leading: Icon(Icons.route, color: colorScheme.primary, size: 20),
                title: const Text('Show Full Route',
                    style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.of(context).pop();
                  onShowRoute!();
                },
              ),
            if ((trip.tripMembers?.length ?? 0) >= 2)
              ListTile(
                dense: true,
                leading: Icon(Icons.psychology,
                    color: colorScheme.secondary, size: 20),
                title: const Text('Group Palate Match',
                    style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/trips/$tripId');
                },
              ),

            const Divider(height: 1),

            // ═══ 2) Stops List ═══
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text('STOPS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[500],
                      letterSpacing: 1)),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: stops.length,
                itemBuilder: (context, index) {
                  final stop = stops[index];
                  final place = stop.place;
                  final isCurrent = index == currentStopIndex;
                  final placeName = place?.name ?? 'Stop ${index + 1}';
                  final placeType = place?.placeType;
                  final city = place?.city ?? '';

                  return Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? colorScheme.primaryContainer
                              .withValues(alpha: 0.5)
                          : null,
                      borderRadius: BorderRadius.circular(10),
                      border: isCurrent
                          ? Border.all(color: colorScheme.primary, width: 2)
                          : null,
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? colorScheme.primary
                              : _placeTypeColor(placeType)
                                  .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: isCurrent
                              ? const Icon(Icons.navigation,
                                  color: Colors.white, size: 18)
                              : Icon(
                                  _placeTypeIcon(placeType),
                                  color: _placeTypeColor(placeType),
                                  size: 18,
                                ),
                        ),
                      ),
                      title: Text(
                        placeName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: city.isNotEmpty
                          ? Text(city,
                              style: const TextStyle(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: isCurrent
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('HERE',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                            )
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      onTap: isCurrent
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              if (onNavigate != null) {
                                onNavigate!(index);
                              } else {
                                context.go('/trips/$tripId/stop/$index');
                              }
                            },
                    ),
                  );
                },
              ),
            ),

            // ═══ 3) Edit / Delete (pinned to bottom) ═══
            if (hasEditDelete) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text('MANAGE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[500],
                        letterSpacing: 1)),
              ),
              if (onEditStop != null)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.edit, color: colorScheme.primary, size: 20),
                  title: const Text('Edit Stop', style: TextStyle(fontSize: 14)),
                  onTap: () {
                    Navigator.of(context).pop();
                    onEditStop!();
                  },
                ),
              if (onDeleteStop != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  title: const Text('Remove Stop',
                      style: TextStyle(fontSize: 14, color: Colors.red)),
                  onTap: () {
                    Navigator.of(context).pop();
                    onDeleteStop!();
                  },
                ),
              if (onEditTrip != null)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_note, color: colorScheme.primary, size: 20),
                  title: const Text('Edit Trip', style: TextStyle(fontSize: 14)),
                  onTap: () {
                    Navigator.of(context).pop();
                    onEditTrip!();
                  },
                ),
              if (onDeleteTrip != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                  title: const Text('Delete Trip',
                      style: TextStyle(fontSize: 14, color: Colors.red)),
                  onTap: () {
                    Navigator.of(context).pop();
                    onDeleteTrip!();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
