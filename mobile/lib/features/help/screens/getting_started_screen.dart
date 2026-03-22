import 'package:flutter/material.dart';

class GettingStartedScreen extends StatefulWidget {
  const GettingStartedScreen({super.key});

  @override
  State<GettingStartedScreen> createState() => _GettingStartedScreenState();
}

class _GettingStartedScreenState extends State<GettingStartedScreen> {
  final _pageCtl = PageController();
  int _currentPage = 0;

  static const _pages = <_WalkthroughPage>[
    _WalkthroughPage(
      icon: Icons.explore,
      title: 'Discover Places',
      description:
          'Browse wineries, breweries, and restaurants. Search by name or explore the map. '
          'Save your favorites for later.',
      color: Colors.deepPurple,
    ),
    _WalkthroughPage(
      icon: Icons.map,
      title: 'Plan Your Trip',
      description:
          'Create a trip, add stops in the order you want to visit them, '
          'and set a date. Invite friends to join along.',
      color: Colors.blue,
    ),
    _WalkthroughPage(
      icon: Icons.check_circle,
      title: 'Check In & Taste',
      description:
          'Start your trip and check in at each stop. Browse the drink menu, '
          'log what you taste, take photos, and rate your experience.',
      color: Colors.teal,
    ),
    _WalkthroughPage(
      icon: Icons.history,
      title: 'Track Your Journey',
      description:
          'Look back at your visit history, see your ratings and tasting notes, '
          'and watch your stats grow on the dashboard.',
      color: Colors.amber,
    ),
  ];

  @override
  void dispose() {
    _pageCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Getting Started'),
        actions: [
          if (!isLast)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageCtl,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) => _buildPage(_pages[i]),
            ),
          ),
          // Page dots
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _currentPage ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _currentPage
                        ? _pages[_currentPage].color
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          // Bottom button
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (isLast) {
                    Navigator.of(context).pop();
                  } else {
                    _pageCtl.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _pages[_currentPage].color,
                ),
                child: Text(isLast ? 'Get Started' : 'Next'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(_WalkthroughPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: page.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 56, color: page.color),
          ),
          const SizedBox(height: 32),
          Text(
            page.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            style: TextStyle(fontSize: 16, color: Colors.grey[600], height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _WalkthroughPage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _WalkthroughPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}
