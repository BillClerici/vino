import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/place.dart';

class FlightBuilderButton extends ConsumerStatefulWidget {
  final Place place;
  final String? tripId;
  final String? visitId;
  final Map<String, dynamic>? existingVisitData;
  const FlightBuilderButton({
    super.key,
    required this.place, this.tripId, this.visitId, this.existingVisitData,
  });

  @override
  ConsumerState<FlightBuilderButton> createState() => _FlightBuilderButtonState();
}

class _FlightBuilderButtonState extends ConsumerState<FlightBuilderButton> {
  Map<String, dynamic>? _flight;
  bool _loading = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void didUpdateWidget(FlightBuilderButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.id != widget.place.id) {
      _flight = null;
      _dismissed = false;
      _loading = false;
      _loadSaved();
    }
  }

  void _loadSaved() {
    final meta = widget.existingVisitData?['metadata'] as Map<String, dynamic>?;
    if (meta != null && meta['flight'] is Map) {
      setState(() => _flight = meta['flight'] as Map<String, dynamic>);
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post(ApiPaths.placeFlight(widget.place.id), data: {'size': 4});
      final data = resp.data['data'] as Map<String, dynamic>? ??
          resp.data as Map<String, dynamic>;
      if (mounted) {
        setState(() { _flight = data; _loading = false; });
        _save(data);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not build flight')),
        );
      }
    }
  }

  Future<void> _save(Map<String, dynamic>? data) async {
    if (widget.tripId == null || widget.visitId == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.post(
        ApiPaths.liveMetadata(widget.tripId!, widget.visitId!),
        data: {'flight': data},
      );
    } catch (_) {}
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'opener': return Colors.green;
      case 'comfort': return Colors.blue;
      case 'stretch': return Colors.orange;
      case 'finisher': return Colors.purple;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    if (_flight == null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _loading ? null : _fetch,
          icon: _loading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.local_bar, size: 16),
          label: Text(_loading ? 'Building flight...' : 'Build Tasting Flight',
              style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10),
            side: BorderSide(color: colorScheme.primary),
          ),
        ),
      );
    }

    final flightName = _flight!['flight_name'] as String? ?? 'Your Flight';
    final description = _flight!['description'] as String? ?? '';
    final items = (_flight!['items'] as List?) ?? [];

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_bar, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(flightName,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                ),
                IconButton(
                  onPressed: _fetch,
                  icon: const Icon(Icons.refresh, size: 16),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  tooltip: 'Build Another',
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () {
                    setState(() { _flight = null; _dismissed = true; });
                    _save(null);
                  },
                  icon: const Icon(Icons.close, size: 16),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            if (description.isNotEmpty)
              Text(description, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 6),
            ...items.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value as Map<String, dynamic>;
              final role = item['role'] as String? ?? '';
              final name = item['name'] as String? ?? '';
              final tip = item['tasting_tip'] as String? ?? '';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: _roleColor(role).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _roleColor(role))),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _roleColor(role).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(role.toUpperCase(),
                                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: _roleColor(role))),
                              ),
                            ],
                          ),
                          if (tip.isNotEmpty)
                            Text(tip, style: TextStyle(fontSize: 10, color: Colors.grey[600], fontStyle: FontStyle.italic)),
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
