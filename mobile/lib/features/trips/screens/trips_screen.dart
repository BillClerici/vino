import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../help/help_launcher.dart';
import '../../../core/widgets/search_bar.dart';
import '../providers/trips_provider.dart';
import '../widgets/sippy_history.dart';
import '../widgets/sippy_planner_chat.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  String? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    final tripsState = ref.watch(tripsProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('My Trips'),
        actions: [const NotificationBell(), helpButton(context, routePrefix: '/trips')],
      ),
      body: Column(
        children: [
          // Search + filter row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: VinoSearchBar(
                    hint: 'Search trips...',
                    onChanged: (q) =>
                        ref.read(tripsProvider.notifier).search(q),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedStatus,
                      hint: const Text('All', style: TextStyle(fontSize: 14)),
                      icon: const Icon(Icons.filter_list, size: 20),
                      style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('All Trips')),
                        for (final s in [
                          ('draft', 'Draft'),
                          ('planning', 'Planning'),
                          ('confirmed', 'Confirmed'),
                          ('in_progress', 'In Progress'),
                          ('completed', 'Completed'),
                          ('cancelled', 'Cancelled'),
                        ])
                          DropdownMenuItem(
                            value: s.$1,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _statusColor(s.$1),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(s.$2),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _selectedStatus = v);
                        ref
                            .read(tripsProvider.notifier)
                            .filterByStatus(v);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: tripsState.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (paginated) {
                if (paginated.items.isEmpty) {
                  return EmptyState(
                    icon: Icons.map,
                    title: 'No trips found',
                    subtitle: _selectedStatus != null
                        ? 'No trips with this status'
                        : 'Plan your first adventure',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(tripsProvider.notifier).refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: paginated.items.length,
                    itemBuilder: (_, i) {
                      final trip = paginated.items[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(trip.status),
                            child: const Icon(Icons.map,
                                color: Colors.white, size: 20),
                          ),
                          title: Text(trip.name),
                          subtitle: Text(
                            [
                              trip.scheduledDate ?? 'No date',
                              '${trip.stopCount} stops',
                              '${trip.memberCount} members',
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await context.push('/trips/${trip.id}');
                            if (context.mounted) {
                              ref.invalidate(tripsProvider);
                            }
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onLongPress: () => openSippyHistory(context, chatType: 'plan'),
            child: FloatingActionButton.extended(
              heroTag: 'plan_with_sippy',
              onPressed: () => openSippyPlanner(context),
              tooltip: 'Plan with Sippy (long-press for history)',
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Sippy', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'create_trip',
            onPressed: () => context.push('/trips/create'),
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return const Color(0xFF7F8C8D);
      case 'planning':
        return const Color(0xFF2980B9);
      case 'confirmed':
        return const Color(0xFF27AE60);
      case 'in_progress':
        return const Color(0xFF1ABC9C);
      case 'completed':
        return const Color(0xFF8E44AD);
      case 'cancelled':
        return const Color(0xFFC0392B);
      default:
        return const Color(0xFF7F8C8D);
    }
  }
}
