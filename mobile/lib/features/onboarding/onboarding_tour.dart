import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/constants.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';

/// Tour steps definition
class _TourStep {
  final String title;
  final String body;
  final IconData icon;
  final Color color;
  const _TourStep({required this.title, required this.body, required this.icon, required this.color});
}

const _tourSteps = [
  _TourStep(
    title: 'Welcome to Trip Me!',
    body: 'Let\'s take a quick tour to show you what you can do. This will only take a minute.',
    icon: Icons.waving_hand,
    color: Color(0xFF5DADE2),
  ),
  _TourStep(
    title: 'Plan Trips with Sippy AI',
    body: 'Tell Sippy where and when you want to go. '
        'Our AI will find places, build an itinerary with times and drive distances, '
        'and let you preview before creating.',
    icon: Icons.auto_awesome,
    color: Color(0xFF2C3E50),
  ),
  _TourStep(
    title: 'Explore Places',
    body: 'Browse wineries, breweries, and restaurants on a map. '
        'Search by name or location, add favorites, and start trips from any place.',
    icon: Icons.explore,
    color: Color(0xFF27AE60),
  ),
  _TourStep(
    title: 'Check In & Log Drinks',
    body: 'When you arrive at a stop, check in to unlock drink logging, '
        'ratings, AI recommendations, food pairings, and tasting flights.',
    icon: Icons.wine_bar,
    color: Color(0xFF8E44AD),
  ),
  _TourStep(
    title: 'AI-Powered Features',
    body: 'Scan wine labels with your camera. '
        'Get personalized recommendations based on your palate. '
        'Build curated tasting flights. Ask Sippy anything!',
    icon: Icons.psychology,
    color: Color(0xFFE67E22),
  ),
  _TourStep(
    title: 'Track Your Journey',
    body: 'View your visit history on a Journey Map. '
        'Earn achievement badges. Build your cellar of purchased wines. '
        'Keep a wishlist of drinks to try.',
    icon: Icons.emoji_events,
    color: Color(0xFFC0392B),
  ),
  _TourStep(
    title: 'You\'re All Set!',
    body: 'Start by planning a trip with Sippy, or explore places near you. '
        'You can always revisit this tour from Help & Guide.',
    icon: Icons.celebration,
    color: Color(0xFF1ABC9C),
  ),
];

/// Shows the onboarding tour as a full-screen overlay.
/// Call this from the dashboard when the user needs onboarding.
void showOnboardingTour(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OnboardingDialog(ref: ref),
  );
}

class _OnboardingDialog extends StatefulWidget {
  final WidgetRef ref;
  const _OnboardingDialog({required this.ref});

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  int _currentStep = 0;
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String status) async {
    try {
      final api = widget.ref.read(apiClientProvider);
      await api.patch(ApiPaths.me, data: {'onboarding_status': status});
      widget.ref.read(authStateProvider.notifier).refreshProfile();
    } catch (_) {}
  }

  void _next() {
    if (_currentStep < _tourSteps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  void _complete() {
    _updateStatus('completed');
    Navigator.of(context).pop();
  }

  void _skip() {
    _updateStatus('skipped');
    Navigator.of(context).pop();
  }

  void _later() {
    _updateStatus('later');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            // Page view
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _tourSteps.length,
                onPageChanged: (i) => setState(() => _currentStep = i),
                itemBuilder: (_, i) {
                  final step = _tourSteps[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(28, 40, 28, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: step.color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(step.icon, size: 40, color: step.color),
                        ),
                        const SizedBox(height: 24),
                        Text(step.title,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text(step.body,
                            style: TextStyle(fontSize: 15, color: Colors.grey[700], height: 1.5),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_tourSteps.length, (i) => Container(
                width: i == _currentStep ? 24 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == _currentStep
                      ? _tourSteps[_currentStep].color
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),
            const SizedBox(height: 16),

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: _currentStep == 0
                  ? Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _next,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: _tourSteps[0].color,
                            ),
                            child: const Text('Let\'s Go!', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _skip,
                              child: Text('Skip', style: TextStyle(color: Colors.grey[500])),
                            ),
                            TextButton(
                              onPressed: _later,
                              child: Text('Maybe Later', style: TextStyle(color: Colors.grey[500])),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        TextButton(
                          onPressed: _skip,
                          child: Text('Skip', style: TextStyle(color: Colors.grey[500])),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: _tourSteps[_currentStep].color,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          ),
                          child: Text(
                            _currentStep == _tourSteps.length - 1 ? 'Get Started!' : 'Next',
                            style: const TextStyle(fontSize: 15),
                          ),
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
