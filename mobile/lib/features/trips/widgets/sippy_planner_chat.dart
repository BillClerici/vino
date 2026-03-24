import 'dart:async' show Timer;

import 'dart:ui' show PointerDeviceKind;

import 'package:dio/dio.dart' show DioException, Options;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/location_service.dart';
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

// ── Structured conversation steps ──────────────────────────────

enum _GatherStep { location, date, startTime, duration, numStops, stopDuration, preferences, ready }

/// Each step: Sippy's question, reaction to the answer, and chips.
class _StepConfig {
  final String question;
  final String Function(String answer) reaction;
  final List<String> Function(String userCity) chips;

  const _StepConfig({
    required this.question,
    required this.reaction,
    required this.chips,
  });
}

final Map<_GatherStep, _StepConfig> _stepConfigs = {
  _GatherStep.location: _StepConfig(
    question: "First things first — where are we headed? Pick a region or tell me a city!",
    reaction: (a) => _locationReaction(a),
    chips: (city) => [
      if (city.isNotEmpty) 'Near me',
      'Napa Valley',
      'Sonoma County',
      'Willamette Valley',
    ],
  ),
  _GatherStep.date: _StepConfig(
    question: "Love it! Now, when are you thinking? Today? This weekend?",
    reaction: (a) => "Got it — marking the calendar for $a.",
    chips: (_) {
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowLabel = DateFormat('EEEE').format(tomorrow);
      return ['Today', 'Tomorrow ($tomorrowLabel)', 'This Saturday', 'This Sunday'];
    },
  ),
  _GatherStep.startTime: _StepConfig(
    question: "What time should we kick things off? Early birds or a leisurely start?",
    reaction: (a) => "Nice, $a it is!",
    chips: (_) => ['10:00 AM', '11:00 AM', 'Noon', '1:00 PM', '2:00 PM'],
  ),
  _GatherStep.duration: _StepConfig(
    question: "How long do you want the whole trip to be? A quick afternoon or an all-day adventure?",
    reaction: (a) => "Perfect — $a gives us plenty to work with!",
    chips: (_) => ['3 hours', '4 hours', '5 hours', '6 hours', 'All day'],
  ),
  _GatherStep.numStops: _StepConfig(
    question: "How many stops are you thinking? I'd suggest 2-3 for a relaxed vibe, or 4-5 if you want to really explore.",
    reaction: (a) => _numStopsReaction(a),
    chips: (_) => ['1 stop', '2 stops', '3 stops', '4 stops', '5 stops'],
  ),
  _GatherStep.stopDuration: _StepConfig(
    question: "About how long at each stop? Enough to taste a few pours, or a longer hang?",
    reaction: (a) => "Sounds perfect — $a per stop.",
    chips: (_) => ['30 minutes', '45 minutes', '1 hour', '90 minutes', '2 hours'],
  ),
  _GatherStep.preferences: _StepConfig(
    question: "Almost there! Anything else I should know? Wine preferences, food cravings, special occasions? Or we can jump right in!",
    reaction: (a) => "Great taste! I'll factor that in.",
    chips: (_) => [
      "I love reds",
      "White wine fan",
      "Craft beer lover",
      "We want food too",
      "Live music please",
      "No preference",
    ],
  ),
};

String _locationReaction(String answer) {
  final lower = answer.toLowerCase();
  if (lower.contains('near me') || lower.contains('near my')) {
    return "I like your style — let's see what's nearby!";
  }
  return "Ooh, $answer is a great pick!";
}

String _numStopsReaction(String answer) {
  final lower = answer.toLowerCase();
  if (lower.contains('1')) return "Quality over quantity — I respect that!";
  if (lower.contains('4') || lower.contains('5')) return "Ambitious! I love it — let's map out an epic route.";
  return "Great choice — that'll be a solid lineup!";
}

// ── Main Chat Widget ───────────────────────────────────────────

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
  String _userCity = '';

  // Structured gathering state
  _GatherStep _currentStep = _GatherStep.location;
  final Map<_GatherStep, String> _answers = {};
  bool _gatheringComplete = false;
  bool _revising = false; // true when user is discussing changes to a proposed trip
  bool _expectingUpdatedPlan = false; // true only after "Update My Trip!" is tapped

  @override
  void initState() {
    super.initState();
    _loadUserCity();
    if (widget.conversationId != null) {
      _conversationId = widget.conversationId;
      _loadConversation();
    } else {
      // Start with Sippy's greeting + first question
      _messages.add({
        'role': 'assistant',
        'content': "Hey there! I'm Sippy, your trip planning buddy. "
            "Let's build you an amazing tasting adventure — I just need a few details!",
      });
      // Small delay before first question to feel natural
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _messages.add({
              'role': 'assistant',
              'content': _stepConfigs[_GatherStep.location]!.question,
            });
          });
          _scrollToBottom();
        }
      });
    }
  }

  Future<void> _loadUserCity() async {
    try {
      final loc = await ref.read(userLocationProvider.future);
      if (mounted && loc != defaultLocation) {
        setState(() => _userCity = 'near me');
      }
    } catch (_) {}
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
      final phase = data['phase'] as String? ?? 'gathering';
      final proposed = data['proposed_trip'] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _messages.addAll(msgs);
          _sessionId = null;
          _phase = phase;
          _gatheringComplete = phase != 'gathering';
          if (phase != 'gathering') _currentStep = _GatherStep.ready;
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

  /// Handle the user's answer during the structured gathering phase.
  void _handleGatherAnswer(String text) {
    // Save this answer
    _answers[_currentStep] = text;

    // Add user message
    setState(() {
      _messages.add({'role': 'user', 'content': text});
    });
    _scrollToBottom();

    // Get Sippy's reaction + next question after a brief delay
    final config = _stepConfigs[_currentStep];
    final reaction = config?.reaction(text) ?? '';
    final nextStep = _nextStep(_currentStep);

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      if (nextStep == _GatherStep.ready) {
        // All required info gathered — show summary + let user add preferences or go
        setState(() {
          _currentStep = _GatherStep.ready;
          _gatheringComplete = true;
          _messages.add({
            'role': 'assistant',
            'content': "$reaction\n\nI've got everything I need! Here's the plan so far:",
          });
          _messages.add({
            'role': 'summary',
            'content': _buildSummaryText(),
          });
          _messages.add({
            'role': 'assistant',
            'content': "Want to add any preferences (wine styles, food, live music), ask me anything about the area, or should I start finding amazing spots?",
          });
        });
        _scrollToBottom();
      } else {
        // Show reaction + next question
        final nextConfig = _stepConfigs[nextStep]!;
        setState(() {
          _currentStep = nextStep;
          _messages.add({
            'role': 'assistant',
            'content': "$reaction ${nextConfig.question}",
          });
        });
        _scrollToBottom();
      }
    });
  }

  _GatherStep _nextStep(_GatherStep current) {
    switch (current) {
      case _GatherStep.location: return _GatherStep.date;
      case _GatherStep.date: return _GatherStep.startTime;
      case _GatherStep.startTime: return _GatherStep.duration;
      case _GatherStep.duration: return _GatherStep.numStops;
      case _GatherStep.numStops:
        // If 1 stop, skip stopDuration (it equals trip duration)
        final answer = (_answers[_GatherStep.numStops] ?? '').toLowerCase();
        if (answer.contains('1')) {
          _answers[_GatherStep.stopDuration] = _answers[_GatherStep.duration] ?? '1 hour';
          return _GatherStep.ready;
        }
        return _GatherStep.stopDuration;
      case _GatherStep.stopDuration: return _GatherStep.ready;
      case _GatherStep.preferences: return _GatherStep.ready;
      case _GatherStep.ready: return _GatherStep.ready;
    }
  }

  String _buildSummaryText() {
    final lines = <String>[];
    if (_answers.containsKey(_GatherStep.location)) {
      lines.add('Location: ${_answers[_GatherStep.location]}');
    }
    if (_answers.containsKey(_GatherStep.date)) {
      lines.add('Date: ${_answers[_GatherStep.date]}');
    }
    if (_answers.containsKey(_GatherStep.startTime)) {
      lines.add('Start: ${_answers[_GatherStep.startTime]}');
    }
    if (_answers.containsKey(_GatherStep.duration)) {
      lines.add('Duration: ${_answers[_GatherStep.duration]}');
    }
    if (_answers.containsKey(_GatherStep.numStops)) {
      lines.add('Stops: ${_answers[_GatherStep.numStops]}');
    }
    if (_answers.containsKey(_GatherStep.stopDuration)) {
      lines.add('Time per stop: ${_answers[_GatherStep.stopDuration]}');
    }
    if (_answers.containsKey(_GatherStep.preferences)) {
      lines.add('Preferences: ${_answers[_GatherStep.preferences]}');
    }
    return lines.join('\n');
  }

  /// Build the structured prompt to send to the LLM with all gathered info.
  String _buildPlannerPrompt() {
    final parts = <String>[];
    parts.add('Plan a trip with these details:');
    if (_answers.containsKey(_GatherStep.location)) {
      parts.add('Location: ${_answers[_GatherStep.location]}');
    }
    if (_answers.containsKey(_GatherStep.date)) {
      parts.add('Date: ${_answers[_GatherStep.date]}');
    }
    if (_answers.containsKey(_GatherStep.startTime)) {
      parts.add('First stop time: ${_answers[_GatherStep.startTime]}');
    }
    if (_answers.containsKey(_GatherStep.duration)) {
      parts.add('Total trip duration: ${_answers[_GatherStep.duration]}');
    }
    if (_answers.containsKey(_GatherStep.numStops)) {
      parts.add('Number of stops: ${_answers[_GatherStep.numStops]}');
    }
    if (_answers.containsKey(_GatherStep.stopDuration)) {
      parts.add('Time at each stop: ${_answers[_GatherStep.stopDuration]}');
    }
    if (_answers.containsKey(_GatherStep.preferences)) {
      parts.add('Preferences: ${_answers[_GatherStep.preferences]}');
    }
    return parts.join('\n');
  }

  /// Get the user's GPS coordinates, or null if unavailable.
  Future<Map<String, double>?> _getUserCoords() async {
    try {
      final loc = await ref.read(userLocationProvider.future);
      if (loc != defaultLocation) {
        return {'lat': loc.latitude, 'lng': loc.longitude};
      }
    } catch (_) {}
    return null;
  }

  /// User wants to add a preference during the ready phase.
  void _handlePreference(String text) {
    final existing = _answers[_GatherStep.preferences] ?? '';
    if (existing.isNotEmpty) {
      _answers[_GatherStep.preferences] = '$existing, $text';
    } else {
      _answers[_GatherStep.preferences] = text;
    }

    setState(() {
      _messages.add({'role': 'user', 'content': text});
    });
    _scrollToBottom();

    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final reactions = [
        "Noted! Anything else, or shall I start planning?",
        "Good to know! Ready to find some great spots, or anything else?",
        "Love it! Want to add more, or should I get to work?",
        "Got it locked in! Ready when you are.",
      ];
      final idx = _messages.length % reactions.length;
      setState(() {
        _messages.add({'role': 'assistant', 'content': reactions[idx]});
      });
      _scrollToBottom();
    });
  }

  /// Kick off the LLM planning with all collected data.
  void _startPlanning() {
    setState(() {
      _messages.add({'role': 'user', 'content': "Let's go, Sippy!"});
    });
    _scrollToBottom();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': "On it! Let me search for the best spots and build your perfect itinerary...",
        });
      });
      _scrollToBottom();

      // Now send structured data to the LLM (bubble already shown above)
      _sendToLLM(message: _buildPlannerPrompt(), showBubble: false);
    });
  }

  /// Enter revision mode — hide preview, show conversation chips.
  void _startRevision(String message) {
    setState(() => _revising = true);
    _sendToLLM(message: message);
  }

  /// User is done revising — ask LLM to produce the updated trip plan.
  void _finishRevision() {
    setState(() {
      _expectingUpdatedPlan = true;
      _messages.add({'role': 'user', 'content': "That's everything — show me the updated trip!"});
    });
    _scrollToBottom();
    _sendToLLM(
      message: 'The user is done requesting changes. Now produce the COMPLETE updated trip plan '
          'with a <trip_plan> JSON block reflecting ALL the changes discussed. '
          'Include every stop, even unchanged ones.',
      showBubble: false,
    );
  }

  /// Build suggestion chips based on the current gathering step.
  List<Widget> _buildSuggestionChips() {
    // Revising mode — user is discussing changes, show go chip to finalize
    if (_revising) {
      return [
        _GoChip("Update My Trip!", onTap: _finishRevision),
        _SuggestionChip('Swap a stop', onTap: (_) => _startRevision('Can you swap one of the stops for a different option?')),
        _SuggestionChip('Change times', onTap: (_) => _startRevision('Can you adjust the timing?')),
        _SuggestionChip('Add a food stop', onTap: (_) => _startRevision('Can you add a restaurant stop?')),
        _SuggestionChip('Remove a stop', onTap: (_) => _startRevision('Can you remove one of the stops?')),
      ];
    }

    // Proposing phase (preview visible) — show revision chips that enter revision mode
    if (_phase == 'proposing') {
      return [
        _SuggestionChip('Swap a stop', onTap: (_) => _startRevision('Can you swap one of the stops for a different option?')),
        _SuggestionChip('Change times', onTap: (_) => _startRevision('Can you adjust the timing?')),
        _SuggestionChip('Add a food stop', onTap: (_) => _startRevision('Can you add a restaurant stop?')),
        _SuggestionChip('Remove a stop', onTap: (_) => _startRevision('Can you remove one of the stops?')),
      ];
    }

    // During structured gathering
    if (!_gatheringComplete) {
      final config = _stepConfigs[_currentStep];
      if (config == null) return [];
      return config.chips(_userCity).map((label) =>
        _SuggestionChip(label, onTap: (t) => _handleGatherAnswer(t)),
      ).toList();
    }

    // Ready phase — preferences + go button
    return [
      _GoChip("Let's Go, Sippy!", onTap: _startPlanning),
      _SuggestionChip('I love reds', onTap: (t) => _handlePreference(t)),
      _SuggestionChip('White wine fan', onTap: (t) => _handlePreference(t)),
      _SuggestionChip('Craft beer', onTap: (t) => _handlePreference(t)),
      _SuggestionChip('Food stops too', onTap: (t) => _handlePreference(t)),
      _SuggestionChip('Live music', onTap: (t) => _handlePreference(t)),
      _SuggestionChip('Pet friendly', onTap: (t) => _handlePreference(t)),
    ];
  }

  /// Handle free-text input from the text field.
  void _handleTextInput() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    if (_gatheringComplete && _phase == 'gathering') {
      // In ready phase — check if user is saying "go", asking a question, or adding preferences
      final lower = text.toLowerCase();
      if (lower.contains("let's go") || lower.contains("plan it") ||
          lower.contains("start planning") || lower.contains("go ahead") ||
          lower.contains("i'm good") || lower.contains("that's it") ||
          lower.contains("ready")) {
        _startPlanning();
      } else if (lower.contains('?') || lower.startsWith('what') ||
          lower.startsWith('how') || lower.startsWith('where') ||
          lower.startsWith('which') || lower.startsWith('are there') ||
          lower.startsWith('do they') || lower.startsWith('can you') ||
          lower.startsWith('tell me')) {
        // User is asking a question — send to LLM for a conversational answer
        setState(() {
          _messages.add({'role': 'user', 'content': text});
        });
        _scrollToBottom();
        _sendToLLM(message: 'Context: I\'m planning a trip with these details:\n${_buildPlannerPrompt()}\n\nUser question: $text\n\nAnswer the question conversationally as a friendly trip guide. Do NOT search for places or propose a trip plan yet — just answer the question.', showBubble: false);
      } else {
        _handlePreference(text);
      }
    } else if (!_gatheringComplete) {
      // Still in gathering phase — accept typed answer for current step
      _handleGatherAnswer(text);
    } else if (_phase == 'proposing' && !_revising) {
      // User is requesting changes to the proposed trip — enter revision mode
      _startRevision(text);
    } else {
      // LLM phase (revising or other) — send as chat message
      _sendToLLM(message: text);
    }
  }

  /// Send a message to the backend LLM (planning/revision phase only).
  /// Set [showBubble] to false if the caller already added the user message.
  Future<void> _sendToLLM({String? message, String? action, bool showBubble = true}) async {
    final text = message ?? _controller.text.trim();
    if (text.isEmpty && action == null) return;
    if (_sending) return;

    final initialThinking = action == 'approve'
        ? 'Creating your trip...'
        : 'Sippy is searching for spots...';

    if (text.isNotEmpty && showBubble) {
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

    // Cycle thinking messages
    final isApproving = action == 'approve';
    final thinkingMessages = isApproving
        ? [
            'Creating your trip...',
            'Setting up your stops...',
            'Calculating drive times...',
            'Adding the finishing touches...',
          ]
        : [
            'Sippy is searching for spots...',
            'Checking menus and reviews...',
            'Building your itinerary...',
            'Mapping out the best route...',
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
      body['history'] = _messages
          .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
          .toList();

      // Include GPS coordinates so the backend can do location-based search
      final coords = await _getUserCoords();
      if (coords != null) {
        body['user_lat'] = coords['lat'];
        body['user_lng'] = coords['lng'];
      }

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
            _revising = false;
            _expectingUpdatedPlan = false;
          } else {
            // Only exit revision mode when we explicitly requested the updated plan
            if (proposedTrip != null && _expectingUpdatedPlan) {
              _revising = false;
              _expectingUpdatedPlan = false;
            }
            _proposedTrip = proposedTrip ?? _proposedTrip;
          }
          _createdTripId = tripId;
          if (convId != null) _conversationId = convId;
          _lastFailedMessage = null;
          _sending = false;
          if (tripId != null) {
            ref.invalidate(tripsProvider);
            ref.invalidate(dashboardProvider);
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      thinkingTimer.cancel();

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

    setState(() {
      if (_messages.isNotEmpty && _messages.last['role'] == 'error') {
        _messages.removeLast();
      }
    });

    if (_lastFailedMessage != null) {
      if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
        _messages.removeLast();
      }
      await _sendToLLM(message: _lastFailedMessage);
    } else if (_conversationId != null) {
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
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
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
                      // Progress indicator during gathering
                      if (!_gatheringComplete && _currentStep != _GatherStep.ready)
                        _GatherProgress(current: _currentStep),
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
                    (_proposedTrip != null && _phase == 'proposing' && !_revising ? 1 : 0) +
                    (_createdTripId != null ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i < _messages.length) {
                    final msg = _messages[i];
                    final role = msg['role'] ?? '';
                    if (role == 'error') {
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
                    if (role == 'summary') {
                      return _SummaryCard(text: msg['content'] ?? '');
                    }
                    return _ChatBubble(
                      text: msg['content'] ?? '',
                      isUser: role == 'user',
                    );
                  }

                  // Trip preview card (hidden during revision mode)
                  final previewIdx = _messages.length;
                  final showPreview = _proposedTrip != null && _phase == 'proposing' && !_revising;
                  if (showPreview && i == previewIdx) {
                    return _TripPreviewCard(
                      trip: _proposedTrip!,
                      onApprove: () => _sendToLLM(message: 'Looks good! Create it.', action: 'approve', showBubble: false),
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
                        _sendToLLM(message: 'Let\'s start over with a different plan.', action: 'reject', showBubble: false);
                      },
                    );
                  }

                  // Created trip card
                  if (_createdTripId != null && i == previewIdx + (showPreview ? 1 : 0)) {
                    return _CreatedTripCard(
                      tripId: _createdTripId!,
                      tripName: _proposedTrip?['name'] as String? ?? 'Your Trip',
                      onView: () {
                        Navigator.of(context).pop();
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

            // Dynamic suggestion chips
            if (_createdTripId == null && !_sending)
              SizedBox(
                height: 44,
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
                    children: _buildSuggestionChips(),
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
                          hintText: _revising
                              ? 'Tell Sippy what to change...'
                              : _phase == 'proposing'
                                  ? 'Request changes to your trip...'
                                  : _gatheringComplete && _phase == 'gathering'
                                      ? 'Add details or tap Let\'s Go...'
                                      : !_gatheringComplete
                                          ? _hintForStep(_currentStep)
                                          : 'Chat with Sippy...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleTextInput(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _handleTextInput,
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

  String _hintForStep(_GatherStep step) {
    switch (step) {
      case _GatherStep.location: return 'City, region, or "near me"...';
      case _GatherStep.date: return 'Today, tomorrow, this Saturday...';
      case _GatherStep.startTime: return '10 AM, noon, 1 PM...';
      case _GatherStep.duration: return '3 hours, 4 hours, all day...';
      case _GatherStep.numStops: return '1-5 stops...';
      case _GatherStep.stopDuration: return '30 min, 1 hour, 90 min...';
      case _GatherStep.preferences: return 'Wine, beer, food preferences...';
      case _GatherStep.ready: return 'Add details or tap Let\'s Go...';
    }
  }
}

// ── Gathering Progress Indicator ─────────────────────────────────

class _GatherProgress extends StatelessWidget {
  final _GatherStep current;
  const _GatherProgress({required this.current});

  int get _stepIndex {
    switch (current) {
      case _GatherStep.location: return 0;
      case _GatherStep.date: return 1;
      case _GatherStep.startTime: return 2;
      case _GatherStep.duration: return 3;
      case _GatherStep.numStops: return 4;
      case _GatherStep.stopDuration: return 5;
      case _GatherStep.preferences: return 6;
      case _GatherStep.ready: return 6;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(6, (i) => Container(
          width: 6, height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i <= _stepIndex ? cs.primary : Colors.grey[300],
          ),
        )),
      ),
    );
  }
}

// ── Summary Card ─────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String text;
  const _SummaryCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = text.split('\n');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text('Your Trip Details',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.primary)),
            ],
          ),
          const SizedBox(height: 8),
          ...lines.map((line) {
            final parts = line.split(': ');
            if (parts.length >= 2) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(_iconForLabel(parts[0]), size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(parts[0], style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(parts.sublist(1).join(': '), style: const TextStyle(fontSize: 12))),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(line, style: const TextStyle(fontSize: 12)),
            );
          }),
        ],
      ),
    );
  }

  IconData _iconForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'location': return Icons.place;
      case 'date': return Icons.calendar_today;
      case 'start': return Icons.access_time;
      case 'duration': return Icons.timer;
      case 'stops': return Icons.pin_drop;
      case 'time per stop': return Icons.hourglass_bottom;
      case 'preferences': return Icons.wine_bar;
      default: return Icons.info_outline;
    }
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
      40,
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

/// A prominent "go" chip for signaling Sippy to start planning.
class _GoChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GoChip(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(Icons.rocket_launch, size: 15, color: cs.onPrimary),
        label: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onPrimary)),
        backgroundColor: cs.primary,
        side: BorderSide.none,
        onPressed: onTap,
      ),
    );
  }
}
