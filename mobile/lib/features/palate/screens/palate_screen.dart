import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../providers/palate_provider.dart';

class PalateScreen extends ConsumerStatefulWidget {
  const PalateScreen({super.key});

  @override
  ConsumerState<PalateScreen> createState() => _PalateScreenState();
}

class _PalateScreenState extends ConsumerState<PalateScreen> {
  bool _analyzing = false;

  Future<void> _analyzePalate() async {
    setState(() => _analyzing = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiPaths.palateAnalyze);
      ref.invalidate(palateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Palate profile updated!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palateState = ref.watch(palateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Palate')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openChat(context),
        icon: const Icon(Icons.chat),
        label: const Text('Ask Sommelier'),
      ),
      body: palateState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // AI Summary card (if profile has been analyzed)
            if (data.profile.preferences.containsKey('summary')) ...[
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome,
                              color: Theme.of(context).colorScheme.secondary),
                          const SizedBox(width: 8),
                          Text('AI Palate Summary',
                              style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.profile.preferences['summary'] as String? ?? '',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (data.profile.lastAnalyzedAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Last analyzed: ${data.profile.lastAnalyzedAt}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Analyze button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _analyzing ? null : _analyzePalate,
                icon: _analyzing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.psychology),
                label: Text(_analyzing
                    ? 'Analyzing your tastings...'
                    : data.profile.preferences.containsKey('summary')
                        ? 'Re-analyze My Palate'
                        : 'Analyze My Palate with AI'),
              ),
            ),
            const SizedBox(height: 16),

            // Taste profile details
            if (data.profile.preferences.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Taste Profile',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      ..._buildProfileRows(data.profile.preferences),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Recommendations
            if (data.profile.preferences.containsKey('recommendations')) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lightbulb_outline, size: 20),
                          const SizedBox(width: 8),
                          Text('Try Next',
                              style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...(data.profile.preferences['recommendations'] as List? ?? [])
                          .map((r) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• '),
                                    Expanded(child: Text('$r')),
                                  ],
                                ),
                              )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Visit stats
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Visit Stats',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _StatRow('Total Visits',
                        '${data.visitStats['total_visits'] ?? 0}'),
                    _StatRow(
                        'Avg Overall',
                        (data.visitStats['avg_overall'] as num?)
                                ?.toStringAsFixed(1) ??
                            '-'),
                    _StatRow(
                        'Avg Staff',
                        (data.visitStats['avg_staff'] as num?)
                                ?.toStringAsFixed(1) ??
                            '-'),
                    _StatRow(
                        'Avg Ambience',
                        (data.visitStats['avg_ambience'] as num?)
                                ?.toStringAsFixed(1) ??
                            '-'),
                    _StatRow(
                        'Avg Food',
                        (data.visitStats['avg_food'] as num?)
                                ?.toStringAsFixed(1) ??
                            '-'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Top varietals
            if (data.topVarietals.isNotEmpty) ...[
              Text('Top Varietals',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...data.topVarietals.map((v) => ListTile(
                    leading: const Icon(Icons.local_drink),
                    title: Text(v['varietal'] as String? ?? ''),
                    subtitle: Text('${v['count']} wines tasted'),
                    trailing: Text(
                      (v['avg_rating'] as num?)?.toStringAsFixed(1) ?? '-',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  )),
            ],

            if (data.topVarietals.isEmpty && data.profile.preferences.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.insights,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        'Log some wine tastings, then tap "Analyze My Palate" to get your AI-generated profile',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

            // Extra padding for FAB
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProfileRows(Map<String, dynamic> prefs) {
    // Show structured profile fields, skip summary and recommendations
    const skipKeys = {'summary', 'recommendations'};
    return prefs.entries
        .where((e) => !skipKeys.contains(e.key))
        .map((e) {
      final label = e.key
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
          .join(' ');
      final value = e.value is List ? (e.value as List).join(', ') : '${e.value}';
      return _StatRow(label, value);
    }).toList();
  }

  void _openChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: const _SommelierChat(),
      ),
    );
  }
}

// ── Sommelier Chat Bottom Sheet ──────────────────────────────────

class _SommelierChat extends ConsumerStatefulWidget {
  const _SommelierChat();

  @override
  ConsumerState<_SommelierChat> createState() => _SommelierChatState();
}

class _SommelierChatState extends ConsumerState<_SommelierChat> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'role': 'assistant',
      'content':
          "Hi! I'm your AI sommelier. Ask me anything about wine, beer, or what you should try next based on your tasting history.",
    });
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
      final resp = await api.post(ApiPaths.palateChat, data: {
        'message': text,
        'history': _messages
            .where((m) => m['role'] != 'assistant' || _messages.indexOf(m) != 0)
            .toList(),
      });
      final data = resp.data['data'] as Map<String, dynamic>? ?? resp.data as Map<String, dynamic>;
      final reply = data['reply'] as String? ?? 'Sorry, I couldn\'t respond.';

      if (mounted) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': reply});
          _sending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': 'Sorry, something went wrong. Please try again.',
          });
          _sending = false;
        });
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

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
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
                      Icon(Icons.auto_awesome,
                          color: Theme.of(context).colorScheme.secondary),
                      const SizedBox(width: 8),
                      Text('AI Sommelier',
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _messages.length) {
                    // Typing indicator
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Thinking...', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  }
                  final msg = _messages[i];
                  final isUser = msg['role'] == 'user';
                  return _ChatBubble(
                    text: msg['content'] ?? '',
                    isUser: isUser,
                  );
                },
              ),
            ),

            // Quick suggestions
            if (_messages.length <= 2)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _SuggestionChip('What should I try next?', onTap: (t) {
                      _controller.text = t;
                      _send();
                    }),
                    _SuggestionChip('Describe my palate', onTap: (t) {
                      _controller.text = t;
                      _send();
                    }),
                    _SuggestionChip('Best wine for dinner?', onTap: (t) {
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
                        hintText: 'Ask your sommelier...',
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
          style: TextStyle(
            color: isUser ? Colors.white : null,
          ),
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

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label)),
          const SizedBox(width: 8),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
