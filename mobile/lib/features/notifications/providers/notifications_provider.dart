import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';

class NotificationItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String? ?? '',
      type: json['notification_type'] as String? ?? 'general',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class NotificationsState {
  final List<NotificationItem> items;
  final int unreadCount;
  final bool loading;

  const NotificationsState({
    this.items = const [],
    this.unreadCount = 0,
    this.loading = false,
  });

  NotificationsState copyWith({
    List<NotificationItem>? items,
    int? unreadCount,
    bool? loading,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      unreadCount: unreadCount ?? this.unreadCount,
      loading: loading ?? this.loading,
    );
  }
}

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  final ApiClient _api;

  NotificationsNotifier(this._api) : super(const NotificationsState());

  Future<void> fetch() async {
    state = state.copyWith(loading: true);
    try {
      final resp = await _api.get(ApiPaths.notifications);
      final data = resp.data is Map && resp.data.containsKey('data')
          ? resp.data['data'] as List
          : resp.data as List;
      final items = data
          .map((j) => NotificationItem.fromJson(j as Map<String, dynamic>))
          .toList();
      final unread = resp.data is Map
          ? (resp.data['unread_count'] as int?) ?? items.where((i) => !i.isRead).length
          : items.where((i) => !i.isRead).length;
      state = NotificationsState(items: items, unreadCount: unread);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _api.post('${ApiPaths.notificationDetail(id)}mark-read/');
      state = state.copyWith(
        items: state.items.map((i) => i.id == id
            ? NotificationItem(
                id: i.id, type: i.type, title: i.title, body: i.body,
                data: i.data, isRead: true, createdAt: i.createdAt)
            : i).toList(),
        unreadCount: (state.unreadCount - 1).clamp(0, 9999),
      );
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _api.post(ApiPaths.notificationMarkAllRead);
      state = state.copyWith(
        items: state.items.map((i) => NotificationItem(
            id: i.id, type: i.type, title: i.title, body: i.body,
            data: i.data, isRead: true, createdAt: i.createdAt)).toList(),
        unreadCount: 0,
      );
    } catch (_) {}
  }

  Future<void> dismiss(String id) async {
    try {
      await _api.delete('${ApiPaths.notificationDetail(id)}dismiss/');
      final wasUnread = state.items.any((i) => i.id == id && !i.isRead);
      state = state.copyWith(
        items: state.items.where((i) => i.id != id).toList(),
        unreadCount: wasUnread
            ? (state.unreadCount - 1).clamp(0, 9999)
            : state.unreadCount,
      );
    } catch (_) {}
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>((ref) {
  final api = ref.read(apiClientProvider);
  return NotificationsNotifier(api);
});
