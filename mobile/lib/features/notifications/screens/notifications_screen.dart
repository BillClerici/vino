import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../providers/notifications_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(notificationsProvider.notifier).fetch();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () => ref.read(notificationsProvider.notifier).markAllRead(),
              child: const Text('Mark All Read'),
            ),
        ],
      ),
      body: state.loading && state.items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('No notifications yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey[500])),
                      const SizedBox(height: 8),
                      Text('Trip reminders and friend activity will show up here',
                          style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(notificationsProvider.notifier).fetch(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                    itemBuilder: (context, i) {
                      final item = state.items[i];
                      return Dismissible(
                        key: ValueKey(item.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          ref.read(notificationsProvider.notifier).dismiss(item.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Notification dismissed'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: _NotificationTile(
                          item: item,
                          onTap: () {
                            if (!item.isRead) {
                              ref.read(notificationsProvider.notifier).markRead(item.id);
                            }
                            final route = item.data['route'] as String?;
                            if (route != null && route.isNotEmpty) {
                              context.go(route);
                            }
                          },
                          onMarkRead: item.isRead
                              ? null
                              : () => ref.read(notificationsProvider.notifier).markRead(item.id),
                          onDismiss: () =>
                              ref.read(notificationsProvider.notifier).dismiss(item.id),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;
  final VoidCallback onDismiss;

  const _NotificationTile({
    required this.item,
    required this.onTap,
    this.onMarkRead,
    required this.onDismiss,
  });

  IconData get _icon {
    switch (item.type) {
      case 'trip_invite': return Icons.mail;
      case 'trip_reminder': return Icons.calendar_today;
      case 'friend_checkin': return Icons.person_pin_circle;
      case 'wishlist_match': return Icons.favorite;
      case 'badge_earned': return Icons.emoji_events;
      case 'trip_started': return Icons.directions_car;
      default: return Icons.notifications;
    }
  }

  Color _iconColor(ColorScheme cs) {
    switch (item.type) {
      case 'trip_invite': return cs.primary;
      case 'trip_reminder': return Colors.orange;
      case 'friend_checkin': return Colors.green;
      case 'wishlist_match': return Colors.red;
      case 'badge_earned': return Colors.amber;
      case 'trip_started': return cs.primary;
      default: return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timeAgo = _formatTimeAgo(item.createdAt);

    return ListTile(
      onTap: onTap,
      tileColor: item.isRead ? null : cs.primaryContainer.withValues(alpha: 0.15),
      leading: CircleAvatar(
        backgroundColor: _iconColor(cs).withValues(alpha: 0.15),
        child: Icon(_icon, color: _iconColor(cs), size: 22),
      ),
      title: Text(
        item.title,
        style: TextStyle(
          fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.body, style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(timeAgo, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(
          item.isRead ? Icons.more_vert : Icons.circle,
          size: item.isRead ? 20 : 8,
          color: item.isRead ? Colors.grey : cs.primary,
        ),
        onSelected: (value) {
          if (value == 'read') onMarkRead?.call();
          if (value == 'dismiss') onDismiss();
        },
        itemBuilder: (_) => [
          if (!item.isRead)
            const PopupMenuItem(value: 'read', child: Text('Mark as read')),
          const PopupMenuItem(value: 'dismiss', child: Text('Dismiss')),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }
}
