import 'package:dio/dio.dart' show Options;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import 'sippy_history.dart';

/// Opens the Ask Sippy chat sheet for a given trip.
/// Pass [conversationId] to resume a previous conversation.
void openSippyChat(BuildContext context, String tripId, {String? conversationId}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: _SippyChat(tripId: tripId, conversationId: conversationId),
    ),
  );
}

class _SippyChat extends ConsumerStatefulWidget {
  final String tripId;
  final String? conversationId;
  const _SippyChat({required this.tripId, this.conversationId});

  @override
  ConsumerState<_SippyChat> createState() => _SippyChatState();
}

class _SippyChatState extends ConsumerState<_SippyChat> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _sending = false;
  bool _loadingHistory = false;
  String? _conversationId;
  String? _lastFailedMessage;

  @override
  void initState() {
    super.initState();
    if (widget.conversationId != null) {
      _conversationId = widget.conversationId;
      _loadConversation();
    } else {
      _messages.add({
        'role': 'assistant',
        'content':
            "Hey! I'm Sippy, your trip assistant. Ask me anything about your stops, "
                "what to order, wine pairings, or how to make the most of your trip!",
      });
    }
  }

  Future<void> _loadConversation() async {
    setState(() => _loadingHistory = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.get(ApiPaths.conversationDetail(_conversationId!));
      final data = resp.data['data'] as Map<String, dynamic>? ??
          resp.data as Map<String, dynamic>;
      final msgs = (data['messages'] as List?)
              ?.map((m) => Map<String, String>.from(m as Map))
              .toList() ??
          [];
      if (mounted) {
        setState(() {
          _messages.addAll(msgs);
          _loadingHistory = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
          _messages.add({
            'role': 'assistant',
            'content': "Couldn't load the conversation. Let's start fresh!",
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final api = ref.read(apiClientProvider);
      final body = <String, dynamic>{
        'message': text,
        'history': _messages
            .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
            .toList(),
      };
      if (_conversationId != null) body['conversation_id'] = _conversationId;

      final resp = await api.dio.post(
        ApiPaths.tripChat(widget.tripId),
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 90)),
      );
      final data = resp.data['data'] as Map<String, dynamic>? ??
          resp.data as Map<String, dynamic>;
      final reply =
          data['reply'] as String? ?? "Sorry, I couldn't respond.";
      final convId = data['conversation_id'] as String?;

      if (mounted) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': reply});
          if (convId != null) _conversationId = convId;
          _lastFailedMessage = null;
          _sending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastFailedMessage = text;
          _messages.add({
            'role': 'error',
            'content': 'Oops, something went wrong.',
          });
          _sending = false;
        });
      }
    }
  }

  Future<void> _retry() async {
    if (_lastFailedMessage == null) return;
    // Remove error message and user message, then resend
    setState(() {
      if (_messages.isNotEmpty && _messages.last['role'] == 'error') {
        _messages.removeLast();
      }
      if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
        _messages.removeLast();
      }
    });
    final text = _lastFailedMessage!;
    _lastFailedMessage = null;
    _controller.text = text;
    _send();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.80,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          children: [
            // Handle + title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
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
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text('S',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.secondary)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Ask Sippy',
                          style: Theme.of(context).textTheme.titleLarge),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          openSippyHistory(context, tripId: widget.tripId, chatType: 'ask');
                        },
                        icon: const Icon(Icons.history),
                        tooltip: 'Chat History',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            if (_loadingHistory)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _messages.length) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Sippy is thinking...',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  }
                  final msg = _messages[i];
                  if (msg['role'] == 'error') {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Text(msg['content'] ?? 'Error',
                              style: const TextStyle(color: Colors.red, fontSize: 13)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _sending ? null : _retry,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    );
                  }
                  final isUser = msg['role'] == 'user';
                  return _ChatBubble(
                    text: msg['content'] ?? '',
                    isUser: isUser,
                  );
                },
              ),
            ),

            // Quick suggestions (only at start)
            if (_messages.length <= 2)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _SuggestionChip('What should I order first?', onTap: (t) {
                      _controller.text = t;
                      _send();
                    }),
                    _SuggestionChip('Best order to visit stops?',
                        onTap: (t) {
                      _controller.text = t;
                      _send();
                    }),
                    _SuggestionChip('Any must-try wines?', onTap: (t) {
                      _controller.text = t;
                      _send();
                    }),
                    _SuggestionChip('Food pairing tips', onTap: (t) {
                      _controller.text = t;
                      _send();
                    }),
                  ],
                ),
              ),

            // Input bar
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Ask Sippy anything...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  const _ChatBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(color: isUser ? Colors.white : null),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final void Function(String) onTap;
  const _SuggestionChip(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: () => onTap(label),
      ),
    );
  }
}
