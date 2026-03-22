import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import 'sippy_chat.dart';
import 'sippy_planner_chat.dart';

/// Shows Sippy conversation history scoped to the given context.
///
/// - For trip-level: pass [tripId] and [chatType] = 'ask'
/// - For planning: pass [chatType] = 'plan', no tripId
void openSippyHistory(
  BuildContext context, {
  String? tripId,
  required String chatType,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) =>
        _SippyHistorySheet(tripId: tripId, chatType: chatType),
  );
}

class _SippyHistorySheet extends ConsumerStatefulWidget {
  final String? tripId;
  final String chatType;
  const _SippyHistorySheet({this.tripId, required this.chatType});

  @override
  ConsumerState<_SippyHistorySheet> createState() => _SippyHistorySheetState();
}

class _SippyHistorySheetState extends ConsumerState<_SippyHistorySheet> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final params = <String, String>{'chat_type': widget.chatType};
      if (widget.tripId != null) params['trip'] = widget.tripId!;

      final resp = await api.get(ApiPaths.conversations, queryParameters: params);
      final data = resp.data['data'] as List? ?? resp.data['results'] as List? ?? [];

      if (mounted) {
        setState(() {
          _conversations = data.map((e) => e as Map<String, dynamic>).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiPaths.conversationDetail(id));
      if (mounted) {
        setState(() {
          _conversations.removeWhere((c) => c['id'] == id);
        });
      }
    } catch (_) {}
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  void _openConversation(Map<String, dynamic> conv) {
    if (!mounted) return;
    final navContext = context;
    final id = conv['id'] as String;
    Navigator.of(navContext).pop(); // close history sheet

    // Open after the sheet closes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.chatType == 'plan') {
        openSippyPlanner(navContext, conversationId: id);
      } else {
        openSippyChat(navContext, widget.tripId!, conversationId: id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.chatType == 'plan'
        ? 'Trip Planning History'
        : 'Sippy Conversations';

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.history, size: 22),
                    const SizedBox(width: 8),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    if (_conversations.isNotEmpty)
                      IconButton(
                        onPressed: () async {
                          if (!mounted) return;
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Clear All?'),
                              content: const Text('Delete all conversations in this view?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && mounted) {
                            for (final c in List.from(_conversations)) {
                              await _delete(c['id'] as String);
                            }
                          }
                        },
                        icon: const Icon(Icons.delete_sweep, size: 20),
                        tooltip: 'Clear All',
                      ),
                    // New conversation button
                    TextButton.icon(
                      onPressed: () {
                        if (!mounted) return;
                        final navContext = context;
                        Navigator.of(navContext).pop();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (widget.chatType == 'plan') {
                            openSippyPlanner(navContext);
                          } else {
                            openSippyChat(navContext, widget.tripId!);
                          }
                        });
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // List
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_conversations.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text('No conversations yet',
                        style: TextStyle(color: Colors.grey[500])),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () {
                        if (!mounted) return;
                        final navContext = context;
                        Navigator.of(navContext).pop();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (widget.chatType == 'plan') {
                            openSippyPlanner(navContext);
                          } else {
                            openSippyChat(navContext, widget.tripId!);
                          }
                        });
                      },
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Start a conversation'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _conversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (_, i) {
                  final conv = _conversations[i];
                  final title = conv['title'] as String? ?? 'Untitled';
                  final phase = conv['phase'] as String? ?? '';
                  final updatedAt = conv['updated_at'] as String?;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        widget.chatType == 'plan' ? Icons.auto_awesome : Icons.chat,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Row(
                      children: [
                        Text(_formatDate(updatedAt),
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        if (phase.isNotEmpty) ...[
                          Text(' · ', style: TextStyle(color: Colors.grey[400])),
                          _PhaseBadge(phase: phase),
                        ],
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      tooltip: 'Delete',
                      onPressed: () async {
                        if (!mounted) return;
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Conversation?'),
                            content: const Text('This cannot be undone.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && mounted) {
                          _delete(conv['id'] as String);
                        }
                      },
                    ),
                    onTap: () => _openConversation(conv),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  final String phase;
  const _PhaseBadge({required this.phase});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (phase) {
      case 'gathering':
        color = Colors.blue;
        label = 'In Progress';
      case 'proposing':
        color = Colors.orange;
        label = 'Preview Ready';
      case 'approved':
        color = Colors.green;
        label = 'Created';
      case 'rejected':
        color = Colors.red;
        label = 'Cancelled';
      default:
        color = Colors.grey;
        label = phase;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }
}
