import 'dart:async' show Timer;
import 'dart:ui' show PointerDeviceKind;

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../config/constants.dart';
import '../../../config/env.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/trip.dart';
import '../../../core/services/google_places_service.dart';
import '../providers/trips_provider.dart';

final _carouselScrollBehavior = const MaterialScrollBehavior().copyWith(
  dragDevices: {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  },
);

class TripDetailScreen extends ConsumerWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripState = ref.watch(tripDetailProvider(tripId));

    return tripState.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Trip')),
        body: Center(child: Text('Error: $e')),
      ),
      data: (trip) => _TripDetailView(trip: trip, tripId: tripId),
    );
  }
}

class _TripDetailView extends ConsumerWidget {
  final Trip trip;
  final String tripId;
  const _TripDetailView({required this.trip, required this.tripId});

  String get _coverImage {
    for (final stop in trip.tripStops ?? []) {
      if (stop.place?.imageUrl.isNotEmpty == true) return stop.place!.imageUrl;
    }
    return '';
  }

  bool get _isOrganizer {
    // Check if current user is the trip creator (organizer)
    // For now, allow editing for all members since we don't have user ID in context
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero Header ──
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            actions: [
              if (_isOrganizer) ...[
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit Trip',
                  onPressed: () => _showEditTripSheet(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete Trip',
                  onPressed: () => _confirmDeleteTrip(context, ref),
                ),
              ],
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (_coverImage.isNotEmpty)
                    Image.network(_coverImage,
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
                  Positioned(
                    left: 20, right: 20, bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(trip.status),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            trip.status.replaceAll('_', ' ').toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(trip.name,
                            style: const TextStyle(
                              color: Colors.white, fontSize: 26,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                            )),
                        const SizedBox(height: 8),
                        Wrap(spacing: 12, runSpacing: 4, children: [
                          if (trip.scheduledDate != null)
                            _IconLabel(Icons.calendar_today, trip.scheduledDate!),
                          _IconLabel(Icons.location_on,
                              '${trip.tripStops?.length ?? 0} stops'),
                          _IconLabel(Icons.people,
                              '${trip.tripMembers?.length ?? 0} members'),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Content ──
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (trip.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Text(trip.description,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ),

                // Meeting details
                if (trip.meetingLocation?.isNotEmpty == true ||
                    trip.meetingTime != null ||
                    trip.scheduledDate != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.meeting_room, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              const Text('Meeting Details',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ]),
                            const Divider(height: 12),
                            // Date, Time, and Stops on same row
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  if (trip.scheduledDate != null) ...[
                                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Text(_formatDate(trip.scheduledDate!),
                                        style: const TextStyle(fontSize: 12)),
                                    const SizedBox(width: 12),
                                  ],
                                  if (trip.meetingTime != null) ...[
                                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Text(_formatTime(trip.meetingTime!),
                                        style: const TextStyle(fontSize: 12)),
                                    const SizedBox(width: 12),
                                  ],
                                  Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text('${trip.tripStops?.length ?? 0} stops',
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            // Show Full Route button
                            if (trip.tripStops != null && trip.tripStops!.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => _TripRouteMapScreen(trip: trip),
                                      ),
                                    ),
                                    icon: const Icon(Icons.route, size: 18),
                                    label: const Text('Show Full Route'),
                                  ),
                                ),
                              ),
                            if (trip.meetingLocation?.isNotEmpty == true)
                              _MeetingRow(Icons.place, 'Location', trip.meetingLocation!),
                            if (trip.transportation?.isNotEmpty == true)
                              _MeetingRow(Icons.directions_car, 'Transportation', trip.transportation!),
                            if (trip.meetingNotes?.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              Text(trip.meetingNotes!,
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Stops ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Row(children: [
                    Text('Stops', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (_isOrganizer)
                      TextButton.icon(
                        onPressed: () => _showAddStopSheet(context, ref),
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('Add Stop'),
                      ),
                  ]),
                ),
                if (trip.tripStops != null && trip.tripStops!.isNotEmpty) ...[
                  _StopsCarousel(stops: trip.tripStops!, tripId: tripId),
                  if (_isOrganizer && trip.tripStops!.length > 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: OutlinedButton.icon(
                        onPressed: () => _showReorderStops(context, ref),
                        icon: const Icon(Icons.swap_vert, size: 18),
                        label: const Text('Reorder Stops'),
                      ),
                    ),
                ] else
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('No stops added yet')),
                      ),
                    ),
                  ),

                // ── Members ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Row(children: [
                    Flexible(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Members', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(width: 8),
                        _CountBadge(count: trip.tripMembers?.length ?? 0),
                      ]),
                    ),
                    if (_isOrganizer)
                      IconButton(
                        onPressed: () => _showInviteMemberSheet(context, ref),
                        icon: const Icon(Icons.person_add_alt),
                        tooltip: 'Invite Member',
                      ),
                  ]),
                ),
                if (trip.tripMembers != null)
                  ...trip.tripMembers!.map((member) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Text(member.displayInitial,
                                  style: TextStyle(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold)),
                            ),
                            title: Text(member.displayName),
                            subtitle: Text(
                              '${member.role.toUpperCase()} · ${_rsvpLabel(member.rsvpStatus)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: _rsvpIcon(member.rsvpStatus),
                            onTap: _isOrganizer
                                ? () => _showEditMemberSheet(context, ref, member)
                                : null,
                          ),
                        ),
                      )),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Edit Trip ─────────────────────────────────────────────────

  Future<void> _confirmDeleteTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Trip?'),
        content: Text(
          'Are you sure you want to delete "${trip.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.delete('${ApiPaths.trips}$tripId/');
      ref.invalidate(tripsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip deleted'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        context.go('/trips');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showEditTripSheet(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditTripSheet(trip: trip, tripId: tripId),
    );
    if (result == true) {
      ref.invalidate(tripDetailProvider(tripId));
    }
  }

  // ── Add Stop ──────────────────────────────────────────────────

  Future<void> _showAddStopSheet(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProviderScope(
          parent: ProviderScope.containerOf(context),
          child: _AddStopScreen(tripId: tripId),
        ),
      ),
    );
    if (result == true) {
      ref.invalidate(tripDetailProvider(tripId));
    }
  }

  // ── Reorder Stops ─────────────────────────────────────────────

  Future<void> _showReorderStops(BuildContext context, WidgetRef ref) async {
    final stops = trip.tripStops ?? [];
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _ReorderStopsSheet(tripId: tripId, stops: stops),
      ),
    );
    if (result == true) {
      ref.invalidate(tripDetailProvider(tripId));
    }
  }

  // ── Invite Member ─────────────────────────────────────────────

  Future<void> _showInviteMemberSheet(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _InviteMemberSheet(tripId: tripId),
      ),
    );
    if (result == true) {
      ref.invalidate(tripDetailProvider(tripId));
    }
  }

  // ── Edit Member ────────────────────────────────────────────────

  Future<void> _showEditMemberSheet(
      BuildContext context, WidgetRef ref, TripMember member) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _EditMemberSheet(tripId: tripId, member: member),
      ),
    );
    if (result == true) {
      ref.invalidate(tripDetailProvider(tripId));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  Widget _gradientBg(ColorScheme cs) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, const Color(0xFF5DADE2)],
          ),
        ),
      );

  Widget _rsvpIcon(String status) {
    switch (status) {
      case 'accepted':
        return const Icon(Icons.check_circle, color: Colors.green, size: 20);
      case 'declined':
        return const Icon(Icons.cancel, color: Colors.red, size: 20);
      default:
        return const Icon(Icons.schedule, color: Colors.orange, size: 20);
    }
  }

  String _rsvpLabel(String status) {
    switch (status) {
      case 'accepted': return 'Accepted';
      case 'declined': return 'Declined';
      default: return 'Pending';
    }
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return DateFormat('MM/dd/yyyy').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  String _formatTime(String time) {
    try {
      final parts = time.split(':');
      if (parts.length >= 2) {
        var hour = int.parse(parts[0]);
        final min = parts[1].padLeft(2, '0');
        final amPm = hour >= 12 ? 'PM' : 'AM';
        if (hour > 12) hour -= 12;
        if (hour == 0) hour = 12;
        return '$hour:$min $amPm';
      }
    } catch (_) {}
    return time;
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'draft': return const Color(0xFF7F8C8D);
      case 'planning': return const Color(0xFF2980B9);
      case 'confirmed': return const Color(0xFF27AE60);
      case 'in_progress': return const Color(0xFF1ABC9C);
      case 'completed': return const Color(0xFF8E44AD);
      case 'cancelled': return const Color(0xFFC0392B);
      default: return const Color(0xFF7F8C8D);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
// TRIP STATUS CARD
// ═══════════════════════════════════════════════════════════════════

class _TripStatusCard extends StatelessWidget {
  final Trip trip;
  const _TripStatusCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(_icon, size: 36, color: _color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _color)),
                  const SizedBox(height: 2),
                  Text(_subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _title {
    switch (trip.status) {
      case 'draft':
      case 'planning':
      case 'confirmed':
        return _countdown;
      case 'in_progress':
        return 'Trip In Progress';
      case 'completed':
        return 'Trip Completed';
      case 'cancelled':
        return 'Trip Cancelled';
      default:
        return trip.status.toUpperCase();
    }
  }

  String get _subtitle {
    switch (trip.status) {
      case 'draft':
      case 'planning':
      case 'confirmed':
        return '${trip.tripStops?.length ?? 0} stops planned · ${trip.tripMembers?.length ?? 0} members';
      case 'in_progress':
        return _inProgressSubtitle;
      case 'completed':
        return _completedSubtitle;
      case 'cancelled':
        return 'This trip was cancelled';
      default:
        return '';
    }
  }

  String get _countdown {
    if (trip.scheduledDate == null) return 'No date set';
    final scheduled = DateTime.tryParse(trip.scheduledDate!);
    if (scheduled == null) return 'No date set';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDay = DateTime(scheduled.year, scheduled.month, scheduled.day);
    final diff = tripDay.difference(today);

    if (diff.isNegative) {
      return '${diff.inDays.abs()} days ago';
    } else if (diff.inDays == 0) {
      return 'Trip is today!';
    } else if (diff.inDays == 1) {
      return 'Trip is tomorrow!';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days to go';
    } else {
      final weeks = diff.inDays ~/ 7;
      final days = diff.inDays % 7;
      if (days == 0) return '$weeks week${weeks > 1 ? 's' : ''} to go';
      return '$weeks week${weeks > 1 ? 's' : ''}, $days day${days > 1 ? 's' : ''} to go';
    }
  }

  String get _inProgressSubtitle {
    final stops = trip.tripStops ?? [];
    if (stops.isEmpty) return 'No stops on this trip';
    // Find next stop with an arrival time in the future
    // For now, just show total stops
    return '${stops.length} stops · Enjoy your trip!';
  }

  String get _completedSubtitle {
    // We don't have check-in counts from the API yet, so show stop count
    final stops = trip.tripStops?.length ?? 0;
    return '$stops stops visited · Trip complete!';
  }

  IconData get _icon {
    switch (trip.status) {
      case 'draft': return Icons.edit_note;
      case 'planning': return Icons.pending_actions;
      case 'confirmed': return Icons.event_available;
      case 'in_progress': return Icons.directions_car;
      case 'completed': return Icons.celebration;
      case 'cancelled': return Icons.event_busy;
      default: return Icons.info;
    }
  }

  Color get _color {
    switch (trip.status) {
      case 'draft': return const Color(0xFF7F8C8D);
      case 'planning': return const Color(0xFF2980B9);
      case 'confirmed': return const Color(0xFF27AE60);
      case 'in_progress': return const Color(0xFF1ABC9C);
      case 'completed': return const Color(0xFF8E44AD);
      case 'cancelled': return const Color(0xFFC0392B);
      default: return const Color(0xFF7F8C8D);
    }
  }
}

class _MeetingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MeetingRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$count',
          style: TextStyle(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 12)),
    );
  }
}

class _IconLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _IconLabel(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      );
}

// ═══════════════════════════════════════════════════════════════════
// EDIT TRIP SHEET
// ═══════════════════════════════════════════════════════════════════

class _EditTripSheet extends StatefulWidget {
  final Trip trip;
  final String tripId;
  const _EditTripSheet({required this.trip, required this.tripId});

  @override
  State<_EditTripSheet> createState() => _EditTripSheetState();
}

class _EditTripSheetState extends State<_EditTripSheet> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _descCtl;
  late final TextEditingController _meetLocCtl;
  late final TextEditingController _meetNotesCtl;
  late final TextEditingController _transportCtl;
  late String _status;
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _meetingTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.trip;
    _nameCtl = TextEditingController(text: t.name);
    _descCtl = TextEditingController(text: t.description);
    _meetLocCtl = TextEditingController(text: t.meetingLocation ?? '');
    _meetNotesCtl = TextEditingController(text: t.meetingNotes ?? '');
    _transportCtl = TextEditingController(text: t.transportation ?? '');
    _status = t.status;
    _startDate = t.scheduledDate != null ? DateTime.tryParse(t.scheduledDate!) : null;
    _endDate = t.endDate != null ? DateTime.tryParse(t.endDate!) : null;
    if (t.meetingTime != null) {
      final parts = t.meetingTime!.split(':');
      if (parts.length >= 2) {
        _meetingTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 12,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    _meetLocCtl.dispose();
    _meetNotesCtl.dispose();
    _transportCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtl.text.isEmpty) return;
    setState(() => _saving = true);
    try {
      final api = ProviderScope.containerOf(context).read(apiClientProvider);
      await api.patch('${ApiPaths.trips}${widget.tripId}/', data: {
        'name': _nameCtl.text,
        'status': _status,
        'description': _descCtl.text,
        'scheduled_date': _startDate != null
            ? DateFormat('yyyy-MM-dd').format(_startDate!)
            : null,
        'end_date': _endDate != null
            ? DateFormat('yyyy-MM-dd').format(_endDate!)
            : null,
        'meeting_time': _meetingTime != null
            ? '${_meetingTime!.hour.toString().padLeft(2, '0')}:${_meetingTime!.minute.toString().padLeft(2, '0')}'
            : null,
        'meeting_location': _meetLocCtl.text,
        'meeting_notes': _meetNotesCtl.text,
        'transportation': _transportCtl.text,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = ['draft', 'planning', 'confirmed', 'in_progress', 'completed', 'cancelled'];
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
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Text('Edit Trip', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _nameCtl, decoration: const InputDecoration(labelText: 'Trip Name')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: statuses.map((s) => DropdownMenuItem(
                value: s,
                child: Text(s.replaceAll('_', ' ').toUpperCase()),
              )).toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 12),
            TextField(controller: _descCtl, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Start Date'),
                  subtitle: Text(_startDate != null ? DateFormat('MMM d, yyyy').format(_startDate!) : 'Not set'),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _startDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                    if (d != null) setState(() => _startDate = d);
                  },
                ),
              ),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('End Date'),
                  subtitle: Text(_endDate != null ? DateFormat('MMM d, yyyy').format(_endDate!) : 'Not set'),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _endDate ?? _startDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                    if (d != null) setState(() => _endDate = d);
                  },
                ),
              ),
            ]),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: const Text('Meeting Time'),
              subtitle: Text(_meetingTime != null ? _meetingTime!.format(context) : 'Not set'),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _meetingTime ?? const TimeOfDay(hour: 10, minute: 0));
                if (t != null) setState(() => _meetingTime = t);
              },
            ),
            TextField(controller: _meetLocCtl, decoration: const InputDecoration(labelText: 'Meeting Location')),
            const SizedBox(height: 12),
            TextField(controller: _meetNotesCtl, maxLines: 2, decoration: const InputDecoration(labelText: 'Meeting Notes')),
            const SizedBox(height: 12),
            TextField(controller: _transportCtl, decoration: const InputDecoration(labelText: 'Transportation')),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Changes'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ADD STOP SHEET
// ═══════════════════════════════════════════════════════════════════

class _AddStopScreen extends ConsumerStatefulWidget {
  final String tripId;
  const _AddStopScreen({required this.tripId});

  @override
  ConsumerState<_AddStopScreen> createState() => _AddStopScreenState();
}

class _AddStopScreenState extends ConsumerState<_AddStopScreen> {
  final _searchCtl = TextEditingController();
  final _placesService = GooglePlacesService();
  List<Map<String, dynamic>> _places = [];
  Map<String, dynamic>? _selectedPlace;
  String _placeType = 'winery';
  bool _loading = false;
  bool _saving = false;
  Set<Marker> _markers = {};
  GoogleMapController? _mapController;
  Timer? _mapIdleTimer;
  bool _initialSearchDone = false;

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
          : '${_placeType == "brewery" ? "breweries" : _placeType == "restaurant" ? "restaurants" : "wineries"}';
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
    // Estimate radius from visible bounds (rough)
    final latDiff =
        (bounds.northeast.latitude - bounds.southwest.latitude).abs();
    final radiusKm = latDiff * 111 / 2; // ~111km per degree
    final radiusMeters = (radiusKm * 1000).clamp(500, 50000).toDouble();

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
    // Don't trigger nearby search until the initial search has completed
    if (!_initialSearchDone) return;
    _mapIdleTimer?.cancel();
    _mapIdleTimer = Timer(const Duration(milliseconds: 800), () {
      if (_searchCtl.text.isEmpty) {
        _searchNearby();
      }
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
        onTap: () => _selectPlace(p),
      ));
    }
  }

  BitmapDescriptor _markerIcon(String type) {
    switch (type) {
      case 'brewery':
        return BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange);
      case 'restaurant':
        return BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen);
      default:
        return BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet);
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
    if (minLat == maxLat) {
      minLat -= 0.05;
      maxLat += 0.05;
    }
    if (minLng == maxLng) {
      minLng -= 0.05;
      maxLng += 0.05;
    }
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng)),
      60,
    ));
  }

  void _selectPlace(Map<String, dynamic> place) {
    setState(() => _selectedPlace = place);
  }

  void _setFilter(String type) {
    setState(() {
      _placeType = type;
      _selectedPlace = null;
    });
    _search();
  }

  Future<void> _addStop() async {
    if (_selectedPlace == null) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final p = _selectedPlace!;

      // First, create the place in our DB (or find existing)
      var name = (p['name'] as String? ?? '').trim();
      final address = (p['address'] as String? ?? '').trim();
      if (name.isEmpty) {
        name = address.isNotEmpty ? address.split(',').first : 'Unknown Place';
      }
      final city = (p['city'] as String? ?? '').trim();
      final state = (p['state'] as String? ?? '').trim();
      var website = (p['website'] as String? ?? '').trim();
      // Ensure website is a valid URL or empty
      if (website.isNotEmpty && !website.startsWith('http')) {
        website = 'https://$website';
      }
      final phone = (p['phone'] as String? ?? '').trim();

      final placeData = <String, dynamic>{
        'name': name.length > 255 ? name.substring(0, 255) : name,
        'place_type': _placeType,
        'address': address.length > 500 ? address.substring(0, 500) : address,
        'city': city.length > 100 ? city.substring(0, 100) : city,
        'state': state.length > 100 ? state.substring(0, 100) : state,
        'website': website,
        'phone': phone.length > 30 ? phone.substring(0, 30) : phone,
      };
      final latRaw = p['latitude'];
      final lngRaw = p['longitude'];
      if (latRaw != null) {
        final latVal = latRaw is double ? latRaw : double.tryParse('$latRaw');
        if (latVal != null) placeData['latitude'] = double.parse(latVal.toStringAsFixed(6));
      }
      if (lngRaw != null) {
        final lngVal = lngRaw is double ? lngRaw : double.tryParse('$lngRaw');
        if (lngVal != null) placeData['longitude'] = double.parse(lngVal.toStringAsFixed(6));
      }
      debugPrint('[AddStop] Creating place: $placeData');
      late final dynamic placeResp;
      try {
        placeResp = await api.post(ApiPaths.places, data: placeData);
      } catch (postError) {
        // Extract response body from DioException
        if (postError is DioException && postError.response != null) {
          debugPrint('[AddStop] Server response: ${postError.response?.data}');
        }
        rethrow;
      }
      debugPrint('[AddStop] Place created: ${placeResp.data}');
      final placeId =
          (placeResp.data['data'] as Map<String, dynamic>)['id'] as String;

      // Then add as a trip stop
      await api.post('${ApiPaths.trips}${widget.tripId}/stops/', data: {
        'place': placeId,
        'duration_minutes': 60,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${p['name']} added as a stop!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e, st) {
      debugPrint('[AddStop] FAILED: $e');
      debugPrint('[AddStop] Stack: $st');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Stop')),
      body: Column(
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
                _FilterChipBtn(
                  label: 'Wineries',
                  icon: Icons.local_drink,
                  selected: _placeType == 'winery',
                  onTap: () => _setFilter('winery'),
                ),
                const SizedBox(width: 8),
                _FilterChipBtn(
                  label: 'Breweries',
                  icon: Icons.sports_bar,
                  selected: _placeType == 'brewery',
                  onTap: () => _setFilter('brewery'),
                ),
                const SizedBox(width: 8),
                _FilterChipBtn(
                  label: 'Restaurants',
                  icon: Icons.restaurant,
                  selected: _placeType == 'restaurant',
                  onTap: () => _setFilter('restaurant'),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
          ),

          // Map + overlay card
          Expanded(
            flex: 3,
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
                // Selected place card overlay
                if (_selectedPlace != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _PlaceCardOverlay(
                      place: _selectedPlace!,
                      saving: _saving,
                      actionLabel: 'Add to Trip',
                      actionIcon: Icons.add_location,
                      onAction: _addStop,
                      onClose: () => setState(() => _selectedPlace = null),
                    ),
                  ),
              ],
            ),
          ),

          // Results list (below map)
          Expanded(
            flex: _selectedPlace != null ? 0 : 2,
            child: _selectedPlace != null
                ? const SizedBox.shrink()
                : _places.isEmpty && !_loading
                    ? Center(
                        child: Text(
                            'Search for ${_placeType == "brewery" ? "breweries" : _placeType == "restaurant" ? "restaurants" : "wineries"} or move the map',
                            style: const TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center))
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: Row(children: [
                              Text('${_places.length} results',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600])),
                              const Spacer(),
                              Text('Tap to select',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600])),
                            ]),
                          ),
                          Expanded(
                            child: ListView.builder(
                                itemCount: _places.length,
                                itemBuilder: (_, i) {
                                  final place = _places[i];
                                  return ListTile(
                                    leading: Icon(Icons.place,
                                        color: _placeType == 'winery'
                                            ? Colors.purple
                                            : _placeType == 'brewery'
                                                ? Colors.orange
                                                : Colors.green),
                                    title: Text(
                                        place['name'] as String? ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                      place['address'] as String? ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    dense: true,
                                    onTap: () => _selectPlace(place),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChipBtn({
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
            Icon(icon,
                size: 16, color: selected ? Colors.white : cs.onSurface),
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

class _PlaceCardOverlay extends StatelessWidget {
  final Map<String, dynamic> place;
  final bool saving;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final VoidCallback onClose;

  const _PlaceCardOverlay({
    required this.place,
    required this.saving,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.onClose,
  });

  String? get _photoUrl {
    // Google Places API (New) returns photos array
    final photos = place['photos'] as List<dynamic>?;
    if (photos != null && photos.isNotEmpty) {
      final photo = photos.first as Map<String, dynamic>;
      final name = photo['name'] as String?;
      if (name != null) {
        final key = EnvConfig.googleMapsApiKey;
        return 'https://places.googleapis.com/v1/$name/media?maxWidthPx=400&key=$key';
      }
    }
    // Fallback: image_url from our DB
    final img = place['image_url'] as String?;
    if (img != null && img.isNotEmpty) return img;
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
          // Image + close button
          SizedBox(
            height: 120,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null)
                  Image.network(photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _placeholderImage(cs))
                else
                  _placeholderImage(cs),
                // Gradient for readability
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
                // Close button
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black38,
                    ),
                  ),
                ),
                // Place type badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      (place['place_type'] as String? ?? 'winery')
                          .toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                // Name overlay
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: Text(
                    place['name'] as String? ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54)
                        ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Details + action button
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.place, size: 16, color: cs.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        place['address'] as String? ?? '',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: saving ? null : onAction,
                    icon: saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Icon(actionIcon, size: 18),
                    label: Text(saving ? 'Adding...' : actionLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderImage(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, const Color(0xFF5DADE2)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.storefront, size: 40, color: Colors.white54),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// REORDER STOPS SHEET
// ═══════════════════════════════════════════════════════════════════

class _ReorderStopsSheet extends ConsumerStatefulWidget {
  final String tripId;
  final List<TripStop> stops;
  const _ReorderStopsSheet({required this.tripId, required this.stops});

  @override
  ConsumerState<_ReorderStopsSheet> createState() => _ReorderStopsSheetState();
}

class _ReorderStopsSheetState extends ConsumerState<_ReorderStopsSheet> {
  late List<TripStop> _stops;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stops = List.from(widget.stops);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('${ApiPaths.trips}${widget.tripId}/stops/reorder/', data: {
        'stops': List.generate(_stops.length, (i) => {
          'id': _stops[i].id,
          'order': '$i',
        }),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Text('Reorder Stops', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Drag to reorder', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: _stops.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _stops.removeAt(oldIndex);
                  _stops.insert(newIndex, item);
                });
              },
              itemBuilder: (_, i) {
                final stop = _stops[i];
                return Card(
                  key: ValueKey(stop.id),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(stop.place?.name ?? 'Unknown'),
                    subtitle: Text(stop.place?.location ?? ''),
                    trailing: const Icon(Icons.drag_handle),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save Order'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// INVITE MEMBER SHEET
// ═══════════════════════════════════════════════════════════════════

class _InviteMemberSheet extends ConsumerStatefulWidget {
  final String tripId;
  const _InviteMemberSheet({required this.tripId});

  @override
  ConsumerState<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends ConsumerState<_InviteMemberSheet> {
  final _emailCtl = TextEditingController();
  final _firstCtl = TextEditingController();
  final _lastCtl = TextEditingController();
  final _messageCtl = TextEditingController();
  bool _saving = false;
  String? _result;

  @override
  void dispose() {
    _emailCtl.dispose();
    _firstCtl.dispose();
    _lastCtl.dispose();
    _messageCtl.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    if (_emailCtl.text.isEmpty) return;
    setState(() {
      _saving = true;
      _result = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final email = _emailCtl.text;
      await api.post('${ApiPaths.trips}${widget.tripId}/members/invite/', data: {
        'email': email,
        'first_name': _firstCtl.text,
        'last_name': _lastCtl.text,
        'message': _messageCtl.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invitation sent to $email!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _result = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Text('Invite Member', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(controller: _emailCtl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _firstCtl, decoration: const InputDecoration(labelText: 'First Name'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _lastCtl, decoration: const InputDecoration(labelText: 'Last Name'))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _messageCtl, maxLines: 3, decoration: const InputDecoration(labelText: 'Personal Message (optional)', hintText: 'Hey! Join us for a wine trip...')),
            const SizedBox(height: 16),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_result!,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _invite,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Send Invitation'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// EDIT MEMBER SHEET
// ═══════════════════════════════════════════════════════════════════

class _EditMemberSheet extends ConsumerStatefulWidget {
  final String tripId;
  final TripMember member;
  const _EditMemberSheet({required this.tripId, required this.member});

  @override
  ConsumerState<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends ConsumerState<_EditMemberSheet> {
  late String _role;
  late String _rsvpStatus;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _role = widget.member.role;
    _rsvpStatus = widget.member.rsvpStatus;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.patch(
        '${ApiPaths.trips}${widget.tripId}/members/${widget.member.id}/',
        data: {'role': _role, 'rsvp_status': _rsvpStatus},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member updated'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _resendInvite() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final email = widget.member.inviteEmail ?? widget.member.user?.email ?? '';
      if (email.isEmpty) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email address available')),
        );
        return;
      }
      await api.post('${ApiPaths.trips}${widget.tripId}/members/invite/', data: {
        'email': email,
        'first_name': widget.member.user?.firstName ?? '',
        'last_name': widget.member.user?.lastName ?? '',
        'message': '',
      });
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invitation resent to $email'), backgroundColor: Colors.green, duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${widget.member.displayName} from this trip?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
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
      await api.delete('${ApiPaths.trips}${widget.tripId}/members/${widget.member.id}/');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member removed'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final roles = ['organizer', 'member', 'invited'];
    final statuses = ['pending', 'accepted', 'declined'];

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
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Text('Edit Member', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // Member info (read-only)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(m.displayInitial,
                        style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (m.inviteEmail != null && m.inviteEmail!.isNotEmpty)
                        Text(m.inviteEmail!, style: Theme.of(context).textTheme.bodySmall),
                      if (m.user?.email != null)
                        Text(m.user!.email, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Role
            DropdownButtonFormField<String>(
              value: roles.contains(_role) ? _role : 'member',
              decoration: const InputDecoration(labelText: 'Role'),
              items: roles.map((r) => DropdownMenuItem(
                value: r,
                child: Text(r[0].toUpperCase() + r.substring(1)),
              )).toList(),
              onChanged: (v) => setState(() => _role = v!),
            ),
            const SizedBox(height: 12),

            // RSVP Status
            DropdownButtonFormField<String>(
              value: statuses.contains(_rsvpStatus) ? _rsvpStatus : 'pending',
              decoration: const InputDecoration(labelText: 'Invitation Status'),
              items: statuses.map((s) {
                IconData icon;
                Color color;
                switch (s) {
                  case 'accepted':
                    icon = Icons.check_circle;
                    color = Colors.green;
                    break;
                  case 'declined':
                    icon = Icons.cancel;
                    color = Colors.red;
                    break;
                  default:
                    icon = Icons.schedule;
                    color = Colors.orange;
                }
                return DropdownMenuItem(
                  value: s,
                  child: Row(children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 8),
                    Text(s[0].toUpperCase() + s.substring(1)),
                  ]),
                );
              }).toList(),
              onChanged: (v) => setState(() => _rsvpStatus = v!),
            ),
            const SizedBox(height: 20),

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes'),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _resendInvite,
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('Resend Invite'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _remove,
                  icon: const Icon(Icons.person_remove, size: 16, color: Colors.red),
                  label: const Text('Remove', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// STOPS CAROUSEL
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
// TRIP ROUTE MAP SCREEN
// ═══════════════════════════════════════════════════════════════════

class _TripRouteMapScreen extends ConsumerStatefulWidget {
  final Trip trip;
  const _TripRouteMapScreen({required this.trip});

  @override
  ConsumerState<_TripRouteMapScreen> createState() => _TripRouteMapScreenState();
}

class _TripRouteMapScreenState extends ConsumerState<_TripRouteMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  // Local copy of distances (filled from API or calculated)
  final Map<int, Map<String, dynamic>> _distances = {};

  @override
  void initState() {
    super.initState();
    _buildMarkersAndRoute();
    _calculateMissingDistances();
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  void _buildMarkersAndRoute() {
    final stops = widget.trip.tripStops ?? [];
    final points = <LatLng>[];

    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];
      final lat = _toDouble(stop.place?.latitude);
      final lng = _toDouble(stop.place?.longitude);
      if (lat == null || lng == null) continue;
      final pos = LatLng(lat, lng);
      points.add(pos);

      // Pre-fill known distances
      if (stop.travelMinutes != null || stop.travelMiles != null) {
        _distances[i] = {
          'minutes': stop.travelMinutes,
          'miles': stop.travelMiles,
        };
      }

      _markers.add(Marker(
        markerId: MarkerId('stop_$i'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          i == 0
              ? BitmapDescriptor.hueGreen
              : i == stops.length - 1
                  ? BitmapDescriptor.hueRed
                  : BitmapDescriptor.hueViolet,
        ),
        infoWindow: InfoWindow(
          title: 'Stop ${i + 1}: ${stop.place?.name ?? ""}',
          snippet: [
            if (stop.durationMinutes != null) '${stop.durationMinutes} min stay',
          ].join(' · '),
        ),
      ));
    }

    if (points.length > 1) {
      _polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: const Color(0xFF2C3E50),
        width: 3,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ));
    }
  }

  Future<void> _calculateMissingDistances() async {
    final stops = widget.trip.tripStops ?? [];
    if (stops.length < 2) return;

    final api = ref.read(apiClientProvider);
    bool changed = false;

    for (int i = 1; i < stops.length; i++) {
      // Skip if already have distance for this stop
      if (_distances.containsKey(i)) continue;

      final prev = stops[i - 1];
      final curr = stops[i];
      final prevLat = _toDouble(prev.place?.latitude);
      final prevLng = _toDouble(prev.place?.longitude);
      final currLat = _toDouble(curr.place?.latitude);
      final currLng = _toDouble(curr.place?.longitude);

      if (prevLat == null || prevLng == null || currLat == null || currLng == null) continue;

      try {
        final resp = await api.get('/api/v1/distance-matrix/', queryParameters: {
          'origins': '$prevLat,$prevLng',
          'destinations': '$currLat,$currLng',
        });
        final data = resp.data['data'] as Map<String, dynamic>;
        final minutes = data['drive_minutes'] as int;
        final miles = (data['miles'] as num).toDouble();

        _distances[i] = {'minutes': minutes, 'miles': miles};
        changed = true;

        // Save to the stop in the DB
        try {
          await api.patch(
            '${ApiPaths.trips}${widget.trip.id}/stops/${curr.id}/',
            data: {'travel_minutes': minutes, 'travel_miles': miles},
          );
        } catch (_) {}
      } catch (_) {}
    }

    if (changed && mounted) {
      setState(() {});
    }
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
        northeast: LatLng(maxLat, maxLng),
      ),
      60,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.trip.tripStops ?? [];

    return Scaffold(
      appBar: AppBar(title: Text('${widget.trip.name} Route')),
      body: Column(
        children: [
          // Map
          Expanded(
            flex: 3,
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: LatLng(35.2271, -80.8431),
                zoom: 8,
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              onMapCreated: (c) {
                _mapController = c;
                Future.delayed(
                    const Duration(milliseconds: 400), _fitBounds);
              },
            ),
          ),
          // Stop list with distances
          Expanded(
            flex: 2,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: stops.length,
              itemBuilder: (_, i) {
                final stop = stops[i];
                final isFirst = i == 0;
                final isLast = i == stops.length - 1;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drive info from previous stop
                    if (!isFirst) ...[
                      () {
                        final dist = _distances[i];
                        final mins = dist?['minutes'] ?? stop.travelMinutes;
                        final mi = dist?['miles'] ?? stop.travelMiles;
                        if (mins != null || mi != null) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 18, bottom: 4, top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.directions_car,
                                    size: 14, color: Colors.grey[500]),
                                const SizedBox(width: 6),
                                Text(
                                  [
                                    if (mins != null) '$mins min',
                                    if (mi != null)
                                      '${mi is double ? mi.toStringAsFixed(1) : mi} mi',
                                  ].join(' · '),
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(left: 18, bottom: 4, top: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                height: 12, width: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: Colors.grey[400]),
                              ),
                              const SizedBox(width: 6),
                              Text('Calculating...',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[400])),
                            ],
                          ),
                        );
                      }(),
                    ],
                    // Stop card
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isFirst
                              ? Colors.green
                              : isLast
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                        title: Text(stop.place?.name ?? 'Unknown',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            stop.place?.location ?? '',
                            if (stop.durationMinutes != null)
                              '${stop.durationMinutes} min stay',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(fontSize: 12),
                        ),
                        dense: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StopsCarousel extends StatefulWidget {
  final List<TripStop> stops;
  final String tripId;
  const _StopsCarousel({required this.stops, required this.tripId});

  @override
  State<_StopsCarousel> createState() => _StopsCarouselState();
}

class _StopsCarouselState extends State<_StopsCarousel> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ScrollConfiguration(
        behavior: _carouselScrollBehavior,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: widget.stops.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final stop = widget.stops[index];
            return SizedBox(
              width: MediaQuery.of(context).size.width * 0.75,
              child: _StopCard(
                stop: stop,
                index: index,
                onTap: () => context.push('/trips/${widget.tripId}/stop/$index'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  final TripStop stop;
  final int index;
  final VoidCallback onTap;
  const _StopCard({required this.stop, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = stop.place?.imageUrl ?? '';
    final grads = [
      [const Color(0xFF2C3E50), const Color(0xFF3498DB)],
      [const Color(0xFF1A3A5C), const Color(0xFF5DADE2)],
      [const Color(0xFF2C3E50), const Color(0xFF1ABC9C)],
      [const Color(0xFF1A2530), const Color(0xFF2980B9)],
    ];

    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Stack(fit: StackFit.expand, children: [
          if (img.isNotEmpty)
            Image.network(img, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: grads[index % grads.length]))))
          else
            Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grads[index % grads.length]))),
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.75)]))),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Stop number badge
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)]),
                child: Center(child: Text('${index + 1}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 15))),
              ),
              const Spacer(),
              // 1) Place Name
              Text(stop.place?.name ?? 'Unknown',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              // 2) Address
              if (stop.place?.location.isNotEmpty == true)
                Text(stop.place!.location,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              // 3) Arrive By Time
              if (stop.arrivalTime != null)
                Row(children: [
                  const Icon(Icons.schedule, size: 12, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text('Arrive ${_formatArrival(stop.arrivalTime!)}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                ]),
              // 4) Drive Distance and Time
              if (stop.travelMinutes != null || stop.travelMiles != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    const Icon(Icons.directions_car, size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(
                      [
                        if (stop.travelMinutes != null) '${stop.travelMinutes} min',
                        if (stop.travelMiles != null) '${stop.travelMiles} mi',
                      ].join(' · '),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  String _formatArrival(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.month}/${dt.day} at $hour:${dt.minute.toString().padLeft(2, '0')} $amPm';
    } catch (_) {
      return isoTime;
    }
  }
}
