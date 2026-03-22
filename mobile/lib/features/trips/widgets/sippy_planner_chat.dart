import 'dart:async' show Timer;

import 'dart:ui' show PointerDeviceKind;

import 'package:dio/dio.dart' show DioException, Options;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../providers/trips_provider.dart';
import 'sippy_history.dart';

/// Opens the Sippy Trip Planner chat as a full-screen modal.
/// Pass [conversationId] to resume a previous conversation.
void openSippyPlanner(BuildContext context, {String? conversationId}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SippyPlannerChat(conversationId: conversationId),
  );
}

class _SippyPlannerChat extends ConsumerStatefulWidget {
  final String? conversationId;
  const _SippyPlannerChat({this.conversationId});

  @override
  ConsumerState<_SippyPlannerChat> createState() => _SippyPlannerChatState();
}

class _SippyPlannerChatState extends ConsumerState<_SippyPlannerChat> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  final List<Map<String, String>> _messages = [];
  bool _sending = false;
  bool _loadingHistory = false;
  String _thinkingText = 'Sippy is thinking...';
  String? _sessionId;
  String? _conversationId;
  String _phase = 'gathering';
  Map<String, dynamic>? _proposedTrip;
  String? _createdTripId;
  String? _lastFailedMessage;

  @override
  void initState() {
    super.initState();
    if (widget.conversationId != null) {
      _conversationId = widget.conversationId;
      _loadConversation();
    } else {
      _messages.add({
        'role': 'welcome',
        'content': '',  // rendered by _WelcomeCard, content ignored
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
      final sessionId = data['session_id'] as String?;
      final phase = data['phase'] as String? ?? 'gathering';
      final proposed = data['proposed_trip'] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _messages.addAll(msgs);
          // Always use a fresh session to avoid corrupt LangGraph checkpoints.
          // The conversation history provides all the context Claude needs.
          _sessionId = null;
          _phase = phase;
          if (proposed != null && proposed.isNotEmpty) _proposedTrip = proposed;
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
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _send({String? overrideText, String? action}) async {
    final text = overrideText ?? _controller.text.trim();
    if (text.isEmpty && action == null) return;
    if (_sending) return;

    final initialThinking = action == 'approve'
        ? 'Creating your trip...'
        : 'Sippy is thinking...';

    if (text.isNotEmpty) {
      setState(() {
        _messages.add({'role': 'user', 'content': text});
        _sending = true;
        _thinkingText = initialThinking;
      });
      _controller.clear();
    } else {
      setState(() {
        _sending = true;
        _thinkingText = initialThinking;
      });
    }
    _scrollToBottom();

    // Cycle thinking messages — context-sensitive
    final isApproving = action == 'approve';
    final thinkingMessages = isApproving
        ? [
            'Creating your trip...',
            'Setting up your stops...',
            'Calculating drive times...',
            'Adding the finishing touches...',
            'Almost ready...',
          ]
        : [
            'Sippy is thinking...',
            'Searching for great places...',
            'Checking menus and reviews...',
            'Building your itinerary...',
            'Almost there...',
          ];
    int thinkingIdx = 0;
    final thinkingTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && _sending) {
        thinkingIdx = (thinkingIdx + 1) % thinkingMessages.length;
        setState(() => _thinkingText = thinkingMessages[thinkingIdx]);
      }
    });

    try {
      final api = ref.read(apiClientProvider);
      final body = <String, dynamic>{};
      if (text.isNotEmpty) body['message'] = text;
      if (action != null) body['action'] = action;
      if (_sessionId != null) body['session_id'] = _sessionId;
      if (_conversationId != null) body['conversation_id'] = _conversationId;
      // Send display history so backend can replay context for fresh sessions
      body['history'] = _messages
          .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
          .toList();

      // Planner calls can take 60-90s (multiple LLM + tool calls)
      final resp = await api.dio.post(
        ApiPaths.tripPlan,
        data: body,
        options: Options(receiveTimeout: const Duration(seconds: 120)),
      );
      final data = resp.data['data'] as Map<String, dynamic>? ??
          resp.data as Map<String, dynamic>;

      final reply = data['reply'] as String? ?? '';
      final phase = data['phase'] as String? ?? 'gathering';
      final sessionId = data['session_id'] as String?;
      final proposedTrip = data['proposed_trip'] as Map<String, dynamic>?;
      final tripId = data['trip_id'] as String?;
      final convId = data['conversation_id'] as String?;

      thinkingTimer.cancel();
      if (mounted) {
        setState(() {
          if (reply.isNotEmpty) {
            _messages.add({'role': 'assistant', 'content': reply});
          }
          _sessionId = sessionId;
          _phase = phase;
          if (phase == 'gathering' || phase == 'rejected') {
            _proposedTrip = null;
          } else {
            _proposedTrip = proposedTrip ?? _proposedTrip;
          }
          _createdTripId = tripId;
          if (convId != null) _conversationId = convId;
          _lastFailedMessage = null;
          _sending = false;
          // Refresh trips list and dashboard if a trip was created
          if (tripId != null) {
            ref.invalidate(tripsProvider);
            ref.invalidate(dashboardProvider);
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      thinkingTimer.cancel();

      // Try to extract a fresh session_id from the error response
      // so retry doesn't hit the corrupt LangGraph checkpoint
      if (e is DioException && e.response?.data is Map) {
        final errData = e.response!.data as Map;
        final newSession = errData['session_id'] as String?;
        final newConvId = errData['conversation_id'] as String?;
        if (newSession != null) _sessionId = newSession;
        if (newConvId != null) _conversationId = newConvId;
      }

      if (mounted) {
        setState(() {
          _lastFailedMessage = text.isNotEmpty ? text : null;
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
    if (_lastFailedMessage == null && _conversationId == null) return;

    // Remove the error message
    setState(() {
      if (_messages.isNotEmpty && _messages.last['role'] == 'error') {
        _messages.removeLast();
      }
    });

    if (_lastFailedMessage != null) {
      // Client-side retry: resend the last message
      // Remove the user message too since _send will re-add it
      if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
        _messages.removeLast();
      }
      await _send(overrideText: _lastFailedMessage);
    } else if (_conversationId != null) {
      // Server-side retry via API
      setState(() => _sending = true);
      try {
        final api = ref.read(apiClientProvider);
        final resp = await api.dio.post(
          ApiPaths.conversationRetry(_conversationId!),
          options: Options(receiveTimeout: const Duration(seconds: 120)),
        );
        final data = resp.data['data'] as Map<String, dynamic>? ??
            resp.data as Map<String, dynamic>;
        final reply = data['reply'] as String? ?? '';

        if (mounted) {
          setState(() {
            if (reply.isNotEmpty) {
              _messages.add({'role': 'assistant', 'content': reply});
            }
            _lastFailedMessage = null;
            _sending = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _messages.add({
              'role': 'error',
              'content': 'Retry failed. Please try again.',
            });
            _sending = false;
          });
        }
      }
    }
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
      height: MediaQuery.of(context).size.height * 0.90,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
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
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text('S',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: colorScheme.primary)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Plan with Sippy',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text('AI Trip Planner',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          openSippyHistory(context, chatType: 'plan');
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
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else
            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length +
                    (_sending ? 1 : 0) +
                    (_proposedTrip != null && _phase == 'proposing' ? 1 : 0) +
                    (_createdTripId != null ? 1 : 0),
                itemBuilder: (_, i) {
                  // Chat messages
                  if (i < _messages.length) {
                    final msg = _messages[i];
                    final isError = msg['role'] == 'error';
                    if (isError) {
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
                    if (msg['role'] == 'welcome') {
                      return _WelcomeCard(
                        onUseExample: (text) {
                          _controller.text = text;
                          setState(() {
                            _messages.removeWhere((m) => m['role'] == 'welcome');
                          });
                        },
                      );
                    }
                    return _ChatBubble(
                      text: msg['content'] ?? '',
                      isUser: msg['role'] == 'user',
                    );
                  }

                  // Trip preview card (after messages, before typing indicator)
                  final previewIdx = _messages.length;
                  if (_proposedTrip != null &&
                      _phase == 'proposing' &&
                      i == previewIdx) {
                    return _TripPreviewCard(
                      trip: _proposedTrip!,
                      onApprove: () => _send(overrideText: 'Looks good! Create it.', action: 'approve'),
                      onReject: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Start Over?'),
                            content: const Text('This will discard the current trip plan. You can always plan a new one.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Keep Plan'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Start Over', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !mounted) return;
                        setState(() {
                          _proposedTrip = null;
                          _phase = 'gathering';
                        });
                        _send(overrideText: 'Let\'s start over with a different plan.', action: 'reject');
                      },
                    );
                  }

                  // Created trip card
                  if (_createdTripId != null && i == previewIdx + (_proposedTrip != null && _phase == 'proposing' ? 1 : 0)) {
                    return _CreatedTripCard(
                      tripId: _createdTripId!,
                      tripName: _proposedTrip?['name'] as String? ?? 'Your Trip',
                      onView: () {
                        Navigator.of(context).pop(); // Close sheet
                        context.go('/trips/$_createdTripId');
                      },
                    );
                  }

                  // Typing indicator
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(_thinkingText,
                              style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Quick suggestions at start
            if (_messages.any((m) => m['role'] == 'welcome') && _createdTripId == null)
              SizedBox(
                height: 40,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _SuggestionChip('Wine trip to Napa today, 4 people, love Pinot', onTap: (t) {
                        _controller.text = t;
                        _send();
                      }),
                      _SuggestionChip('Brewery tour this Saturday near Portland', onTap: (t) {
                        _controller.text = t;
                        _send();
                      }),
                      _SuggestionChip('Sonoma wine day tomorrow, start at 11am, 3 stops', onTap: (t) {
                        _controller.text = t;
                        _send();
                      }),
                    ],
                  ),
                ),
              ),

            // Input bar (hidden if trip was created)
            if (_createdTripId == null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _inputFocusNode,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: _phase == 'proposing'
                              ? 'Request changes or approve...'
                              : 'Describe your ideal trip...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : () => _send(),
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

// ── Trip Preview Card ────────────────────────────────────────────

class _TripPreviewCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _TripPreviewCard({
    required this.trip,
    required this.onApprove,
    required this.onReject,
  });

  bool _hasCoordinates(List stops) {
    int count = 0;
    for (final s in stops) {
      final place = (s as Map<String, dynamic>)['place'] as Map<String, dynamic>? ?? {};
      if (place['latitude'] != null && place['longitude'] != null) count++;
    }
    return count >= 2;
  }

  IconData _placeTypeIcon(String? type) {
    switch (type) {
      case 'winery': return Icons.wine_bar;
      case 'brewery': return Icons.sports_bar;
      case 'restaurant': return Icons.restaurant;
      default: return Icons.place;
    }
  }

  Color _placeTypeColor(String? type) {
    switch (type) {
      case 'winery': return const Color(0xFF8E44AD);
      case 'brewery': return Colors.orange;
      case 'restaurant': return Colors.green;
      default: return Colors.blueGrey;
    }
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String _formatTime(String hhmm) {
    try {
      final parts = hhmm.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? parts[1] : '00';
      final amPm = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $amPm';
    } catch (_) {
      return hhmm;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stops = (trip['stops'] as List?) ?? [];
    final name = trip['name'] as String? ?? 'Trip';
    final scheduledDate = trip['scheduled_date'] as String? ?? '';
    final endDate = trip['end_date'] as String? ?? '';
    final isSameDay = endDate.isEmpty || endDate == scheduledDate;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 18),
                    SizedBox(width: 8),
                    Text('TRIP PREVIEW',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (scheduledDate.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey[700]),
                      const SizedBox(width: 6),
                      Text(
                        isSameDay
                            ? _formatDate(scheduledDate)
                            : '${_formatDate(scheduledDate)} — ${_formatDate(endDate)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                if (stops.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.place, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        '${stops.length} stops',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      if (stops.first is Map &&
                          (stops.first as Map)['arrival_time'] != null &&
                          ((stops.first as Map)['arrival_time'] as String).isNotEmpty) ...[
                        Text(' · ', style: TextStyle(color: Colors.grey[400])),
                        Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Starts ${_formatTime((stops.first as Map)['arrival_time'] as String)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Stops
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: List.generate(stops.length, (i) {
                final stop = stops[i] as Map<String, dynamic>;
                final place = stop['place'] as Map<String, dynamic>? ?? {};
                final placeName = place['name'] as String? ?? 'Stop ${i + 1}';
                final city = place['city'] as String? ?? '';
                final state = place['state'] as String? ?? '';
                final placeType = place['place_type'] as String? ?? 'winery';
                final duration = stop['duration_minutes'] as int? ?? 60;
                final notes = stop['notes'] as String? ?? '';
                final arrivalTime = stop['arrival_time'] as String? ?? '';
                final location = [city, state].where((s) => s.isNotEmpty).join(', ');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Arrival time column — match 28px icon height for alignment
                      SizedBox(
                        width: 52,
                        height: 28,
                        child: Align(
                          alignment: Alignment.center,
                          child: arrivalTime.isNotEmpty
                              ? Text(
                                  _formatTime(arrivalTime),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                )
                              : Text('Stop ${i + 1}',
                                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        ),
                      ),
                      // Timeline dot + line
                      Column(
                        children: [
                          Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: _placeTypeColor(placeType).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(_placeTypeIcon(placeType),
                                  size: 14, color: _placeTypeColor(placeType)),
                            ),
                          ),
                          if (i < stops.length - 1)
                            Container(
                              width: 2, height: 24,
                              color: Colors.grey[300],
                            ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(placeName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            if (location.isNotEmpty)
                              Text(location,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            Row(
                              children: [
                                Icon(Icons.timer_outlined, size: 12, color: Colors.grey[500]),
                                const SizedBox(width: 4),
                                Text('~$duration min',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                              ],
                            ),
                            if (notes.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(notes,
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),

          // Route map
          if (_hasCoordinates(stops))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 150,
                  child: _PreviewRouteMap(stops: stops),
                ),
              ),
            ),

          // Hint + action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Text(
              'Type below to request changes, or approve:',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Looks Good!'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Start Over',
                  style: IconButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Created Trip Success Card ────────────────────────────────────

class _CreatedTripCard extends StatelessWidget {
  final String tripId;
  final String tripName;
  final VoidCallback onView;

  const _CreatedTripCard({
    required this.tripId,
    required this.tripName,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.green[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.celebration, size: 40, color: Colors.green),
            const SizedBox(height: 12),
            Text('Trip Created!',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(tripName, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onView,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('View Trip'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared Widgets ──────────────────────────────────────────────

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

class _WelcomeCard extends StatelessWidget {
  final void Function(String) onUseExample;
  const _WelcomeCard({required this.onUseExample});

  static const _examplePrompt =
      "My wife and I would like to visit 3 wineries today starting "
      "around noon near I-77 in northern NC. We want to visit each "
      "stop for 60-90 minutes and keep drive time between stops to "
      "less than 20 minutes. We like both red and white wines. "
      "We also like live music.";

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sippy greeting bubble
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              "Hey, I'm Sippy! Tell me about the trip you're dreaming up — "
              "the more detail you give me upfront, the faster we'll get rolling!",
            ),
          ),
        ),

        // What I need card
        Container(
          margin: const EdgeInsets.only(bottom: 8, right: 32),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.checklist, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text("What I'll ask you",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary)),
                ],
              ),
              const SizedBox(height: 8),
              _CheckItem(icon: Icons.place, text: 'Where do you want to go?'),
              _CheckItem(icon: Icons.calendar_today, text: 'What date?'),
              _CheckItem(icon: Icons.access_time, text: 'What time to start?'),
              _CheckItem(icon: Icons.wine_bar, text: 'What do you like to drink?'),
              _CheckItem(icon: Icons.timer, text: 'How long at each stop?'),
              _CheckItem(icon: Icons.route, text: 'Max drive time between stops?'),
              _CheckItem(icon: Icons.music_note, text: 'Events or live music?'),
              const SizedBox(height: 4),
              Text('Include as many as you can in your first message!',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic)),
            ],
          ),
        ),

        // Example prompt card
        Container(
          margin: const EdgeInsets.only(bottom: 8, right: 32),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: colorScheme.secondary),
                  const SizedBox(width: 6),
                  Text('Example prompt',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.secondary)),
                ],
              ),
              const SizedBox(height: 8),
              Text(_examplePrompt,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700], fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  onPressed: () => onUseExample(_examplePrompt),
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('Use as template', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    side: BorderSide(color: colorScheme.secondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CheckItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ),
    );
  }
}

class _PreviewRouteMap extends StatefulWidget {
  final List stops;
  const _PreviewRouteMap({required this.stops});

  @override
  State<_PreviewRouteMap> createState() => _PreviewRouteMapState();
}

class _PreviewRouteMapState extends State<_PreviewRouteMap> {
  GoogleMapController? _controller;

  List<LatLng> get _points {
    final pts = <LatLng>[];
    for (final s in widget.stops) {
      final place = (s as Map<String, dynamic>)['place'] as Map<String, dynamic>? ?? {};
      final lat = place['latitude'];
      final lng = place['longitude'];
      if (lat != null && lng != null) {
        pts.add(LatLng((lat as num).toDouble(), (lng as num).toDouble()));
      }
    }
    return pts;
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};
    final points = _points;
    for (var i = 0; i < points.length; i++) {
      final stop = widget.stops[i] as Map<String, dynamic>;
      final place = stop['place'] as Map<String, dynamic>? ?? {};
      final name = place['name'] as String? ?? 'Stop ${i + 1}';
      markers.add(Marker(
        markerId: MarkerId('stop_$i'),
        position: points[i],
        infoWindow: InfoWindow(title: name),
      ));
    }
    return markers;
  }

  Set<Polyline> get _polylines {
    final points = _points;
    if (points.length < 2) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: const Color(0xFF2C3E50),
        width: 3,
      ),
    };
  }

  void _fitBounds() {
    final points = _points;
    if (points.isEmpty || _controller == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    _controller!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      40, // padding
    ));
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    if (points.isEmpty) return const SizedBox.shrink();

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: points.first,
        zoom: 10,
      ),
      onMapCreated: (controller) {
        _controller = controller;
        // Delay to let the map render before fitting bounds
        Future.delayed(const Duration(milliseconds: 300), _fitBounds);
      },
      markers: _markers,
      polylines: _polylines,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      scrollGesturesEnabled: false,
      zoomGesturesEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
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
