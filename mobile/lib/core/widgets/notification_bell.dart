import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/providers/notifications_provider.dart';

class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(notificationsProvider.notifier).fetch());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final unread = state.unreadCount;

    return IconButton(
      onPressed: () => context.go('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread', style: const TextStyle(fontSize: 10)),
        child: const Icon(Icons.notifications_outlined),
      ),
      tooltip: 'Notifications',
    );
  }
}
