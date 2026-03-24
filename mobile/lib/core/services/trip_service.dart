import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/constants.dart';
import '../api/api_client.dart';

/// Data collected from the Start Trip bottom sheet.
class StartTripInput {
  final String tripName;
  final DateTime startDate;
  final Duration totalDuration;
  final TimeOfDay firstStopTime;

  const StartTripInput({
    required this.tripName,
    required this.startDate,
    required this.totalDuration,
    required this.firstStopTime,
  });

  String get scheduledDate => DateFormat('yyyy-MM-dd').format(startDate);

  String get endDate {
    final endDt = startDate.add(totalDuration);
    return DateFormat('yyyy-MM-dd').format(endDt);
  }

  String get meetingTime =>
      '${firstStopTime.hour.toString().padLeft(2, '0')}:${firstStopTime.minute.toString().padLeft(2, '0')}';
}

/// Shows a bottom sheet to collect trip start details.
/// Returns null if the user cancels.
/// [initialName] pre-fills the trip name (e.g. "Trip to Sonoma Winery").
Future<StartTripInput?> showStartTripSheet(
  BuildContext context, {
  String initialName = '',
}) {
  return showModalBottomSheet<StartTripInput>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StartTripSheet(initialName: initialName),
  );
}

/// Creates a new trip from a place and navigates to the trip detail.
/// Used by Explore list, Favorites, Map, and Place Detail screens.
Future<void> startTripFromPlace({
  required BuildContext context,
  required WidgetRef ref,
  required String placeId,
  required String placeName,
}) async {
  // Show the start-trip setup sheet with prefilled name
  final input = await showStartTripSheet(
    context,
    initialName: 'Trip to $placeName',
  );
  if (input == null || !context.mounted) return;

  final api = ref.read(apiClientProvider);

  try {
    // Create the trip
    final tripResp = await api.post(ApiPaths.trips, data: {
      'name': input.tripName,
      'status': 'draft',
      'scheduled_date': input.scheduledDate,
      'end_date': input.endDate,
      'meeting_time': input.meetingTime,
    });
    final tripData = tripResp.data['data'] as Map<String, dynamic>;
    final tripId = tripData['id'] as String;

    // Add the place as the first stop
    await api.post('${ApiPaths.trips}$tripId/stops/', data: {
      'place': placeId,
      'duration_minutes': 60,
    });

    if (context.mounted) {
      context.go('/trips/$tripId');
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error creating trip: $e')));
    }
  }
}

/// Same as above but for Google Places data (not yet in our DB).
Future<void> startTripFromGooglePlace({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> place,
  required String placeType,
}) async {
  final api = ref.read(apiClientProvider);

  try {
    // Create place in DB first
    var name = (place['name'] as String? ?? '').trim();
    if (name.isEmpty) name = 'Unknown Place';
    final address = (place['address'] as String? ?? '').trim();
    var website = (place['website'] as String? ?? '').trim();
    if (website.isNotEmpty && !website.startsWith('http')) {
      website = 'https://$website';
    }

    final placeData = <String, dynamic>{
      'name': name,
      'place_type': placeType,
      'address': address,
      'city': (place['city'] as String? ?? '').trim(),
      'state': (place['state'] as String? ?? '').trim(),
      'website': website,
      'phone': (place['phone'] as String? ?? '').trim(),
    };
    final lat = place['latitude'];
    final lng = place['longitude'];
    if (lat != null) {
      final v = lat is double ? lat : double.tryParse('$lat');
      if (v != null) placeData['latitude'] = double.parse(v.toStringAsFixed(6));
    }
    if (lng != null) {
      final v = lng is double ? lng : double.tryParse('$lng');
      if (v != null) placeData['longitude'] = double.parse(v.toStringAsFixed(6));
    }

    final placeResp = await api.post(ApiPaths.places, data: placeData);
    final placeId =
        (placeResp.data['data'] as Map<String, dynamic>)['id'] as String;

    if (context.mounted) {
      await startTripFromPlace(
        context: context,
        ref: ref,
        placeId: placeId,
        placeName: name,
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// START TRIP BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════

class StartTripSheet extends StatefulWidget {
  final String initialName;
  const StartTripSheet({super.key, this.initialName = ''});

  @override
  State<StartTripSheet> createState() => _StartTripSheetState();
}

class _StartTripSheetState extends State<StartTripSheet> {
  late final TextEditingController _nameCtl;
  late DateTime _startDate;
  int _durationHours = 4;
  int _durationMinutes = 0;
  late TimeOfDay _firstStopTime;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.initialName);
    _startDate = DateTime.now();
    _firstStopTime = const TimeOfDay(hour: 12, minute: 0);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _firstStopTime,
    );
    if (picked != null) setState(() => _firstStopTime = picked);
  }

  void _submit() {
    if (_nameCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a trip name'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    Navigator.of(context).pop(StartTripInput(
      tripName: _nameCtl.text.trim(),
      startDate: _startDate,
      totalDuration: Duration(hours: _durationHours, minutes: _durationMinutes),
      firstStopTime: _firstStopTime,
    ));
  }

  String get _endDateLabel {
    final endDt = _startDate.add(
        Duration(hours: _durationHours, minutes: _durationMinutes));
    if (endDt.year == _startDate.year &&
        endDt.month == _startDate.month &&
        endDt.day == _startDate.day) {
      return 'Same day';
    }
    return DateFormat('MMM d, yyyy').format(endDt);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Title
            Row(
              children: [
                Icon(Icons.directions_car, color: cs.primary),
                const SizedBox(width: 10),
                Text('Plan a Trip',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 20),

            // ── Trip Name ──
            TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(
                labelText: 'Trip Name *',
                hintText: 'e.g. Napa Valley Weekend',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            // ── Trip Start Date ──
            _FieldTile(
              icon: Icons.calendar_today,
              label: 'Trip Date',
              value: DateFormat('EEE, MMM d, yyyy').format(_startDate),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),

            // ── Total Duration ──
            Text('Total Duration',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 20, color: cs.primary.withValues(alpha: 0.7)),
                const SizedBox(width: 12),
                // Hours spinner
                _SpinnerField(
                  value: _durationHours,
                  label: 'hr',
                  min: 0,
                  max: 24,
                  onChanged: (v) => setState(() => _durationHours = v),
                ),
                const SizedBox(width: 16),
                // Minutes spinner
                _SpinnerField(
                  value: _durationMinutes,
                  label: 'min',
                  min: 0,
                  max: 45,
                  step: 15,
                  onChanged: (v) => setState(() => _durationMinutes = v),
                ),
                const Spacer(),
                // End date preview
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_forward, size: 12, color: cs.outline),
                      const SizedBox(width: 4),
                      Text(_endDateLabel,
                          style: TextStyle(fontSize: 12, color: cs.outline)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── First Stop Time ──
            _FieldTile(
              icon: Icons.access_time,
              label: 'First Stop Time',
              value: _firstStopTime.format(context),
              onTap: _pickTime,
            ),
            const SizedBox(height: 24),

            // ── Buttons ──
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.directions_car),
                    label: const Text('Create Trip'),
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

/// A tappable field row with icon, label, and value.
class _FieldTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _FieldTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.5))),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }
}

/// A compact +/- spinner for numeric values.
class _SpinnerField extends StatelessWidget {
  final int value;
  final String label;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _SpinnerField({
    required this.value,
    required this.label,
    this.min = 0,
    this.max = 99,
    this.step = 1,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: value > min ? () => onChanged(value - step) : null,
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Icon(Icons.remove,
                  size: 16,
                  color: value > min ? cs.primary : cs.outline),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('$value $label',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          InkWell(
            onTap: value < max ? () => onChanged(value + step) : null,
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Icon(Icons.add,
                  size: 16,
                  color: value < max ? cs.primary : cs.outline),
            ),
          ),
        ],
      ),
    );
  }
}
