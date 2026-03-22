import 'package:flutter/material.dart';

enum HelpCategory {
  gettingStarted('Getting Started', Icons.rocket_launch),
  dashboard('Dashboard', Icons.dashboard),
  trips('Trips', Icons.map),
  stops('Stops & Drinks', Icons.place),
  drinks('Drinks', Icons.local_drink),
  visits('Visits', Icons.history),
  explore('Explore', Icons.explore),
  profile('Profile', Icons.person);

  final String label;
  final IconData icon;
  const HelpCategory(this.label, this.icon);
}

class HelpArticle {
  final String id;
  final String title;
  final HelpCategory category;
  final IconData icon;
  final List<String> keywords;
  final List<HelpSection> sections;
  final String? relatedRoutePrefix;

  const HelpArticle({
    required this.id,
    required this.title,
    required this.category,
    required this.icon,
    this.keywords = const [],
    required this.sections,
    this.relatedRoutePrefix,
  });

  String get preview {
    for (final s in sections) {
      if (s.body.isNotEmpty) {
        return s.body.length > 100 ? '${s.body.substring(0, 100)}...' : s.body;
      }
    }
    return '';
  }
}

class HelpSection {
  final String? heading;
  final String body;
  final String? tipText;
  final IconData? stepIcon;

  const HelpSection({
    this.heading,
    this.body = '',
    this.tipText,
    this.stepIcon,
  });
}
