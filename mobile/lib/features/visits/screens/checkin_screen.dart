import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/rating_stars.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../help/help_launcher.dart';

class CheckinScreen extends ConsumerStatefulWidget {
  final String? placeId;
  const CheckinScreen({super.key, this.placeId});

  @override
  ConsumerState<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends ConsumerState<CheckinScreen> {
  final _notesController = TextEditingController();
  String? _selectedPlaceId;
  int? _ratingOverall;
  int? _ratingStaff;
  int? _ratingAmbience;
  int? _ratingFood;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedPlaceId = widget.placeId;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedPlaceId == null) return;
    setState(() => _submitting = true);

    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiPaths.visits, data: {
        'place': _selectedPlaceId,
        'visited_at': DateTime.now().toIso8601String(),
        'rating_overall': _ratingOverall,
        'rating_staff': _ratingStaff,
        'rating_ambience': _ratingAmbience,
        'rating_food': _ratingFood,
        'notes': _notesController.text,
      });
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check In'),
        actions: [const NotificationBell(), helpButton(context, routePrefix: '/visits')],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Rate your visit',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _RatingField(
            label: 'Overall',
            rating: _ratingOverall,
            onChanged: (v) => setState(() => _ratingOverall = v),
          ),
          _RatingField(
            label: 'Staff',
            rating: _ratingStaff,
            onChanged: (v) => setState(() => _ratingStaff = v),
          ),
          _RatingField(
            label: 'Ambience',
            rating: _ratingAmbience,
            onChanged: (v) => setState(() => _ratingAmbience = v),
          ),
          _RatingField(
            label: 'Food & Drinks',
            rating: _ratingFood,
            onChanged: (v) => setState(() => _ratingFood = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'How was your visit?',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Check-In'),
          ),
        ],
      ),
    );
  }
}

class _RatingField extends StatelessWidget {
  final String label;
  final int? rating;
  final ValueChanged<int> onChanged;

  const _RatingField({
    required this.label,
    this.rating,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label),
          ),
          RatingStars(rating: rating, size: 28, onChanged: onChanged),
        ],
      ),
    );
  }
}
