import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';

class TripCreateScreen extends ConsumerStatefulWidget {
  const TripCreateScreen({super.key});

  @override
  ConsumerState<TripCreateScreen> createState() => _TripCreateScreenState();
}

class _TripCreateScreenState extends ConsumerState<TripCreateScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  DateTime _scheduledDate = DateTime.now();
  DateTime? _endDate;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameController.text.isEmpty) return;
    setState(() => _submitting = true);

    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.post(ApiPaths.trips, data: {
        'name': _nameController.text,
        'description': _descController.text,
        'scheduled_date': DateFormat('yyyy-MM-dd').format(_scheduledDate),
        if (_endDate != null)
          'end_date': DateFormat('yyyy-MM-dd').format(_endDate!),
      });
      if (mounted) {
        final tripId = (resp.data['data'] as Map<String, dynamic>)['id'];
        context.go('/trips/$tripId');
      }
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
      appBar: AppBar(title: const Text('Plan a Trip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Trip Name'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Start Date'),
            subtitle:
                Text(DateFormat('MMM d, yyyy').format(_scheduledDate)),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _scheduledDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) setState(() => _scheduledDate = date);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('End Date (optional)'),
            subtitle: Text(_endDate != null
                ? DateFormat('MMM d, yyyy').format(_endDate!)
                : 'Not set'),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _endDate ?? _scheduledDate,
                firstDate: _scheduledDate,
                lastDate: _scheduledDate.add(const Duration(days: 30)),
              );
              if (date != null) setState(() => _endDate = date);
            },
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
                : const Text('Create Trip'),
          ),
        ],
      ),
    );
  }
}
