import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/help_content.dart';
import 'models/help_article.dart';

/// Returns a help IconButton for use in AppBar actions.
/// Pass [routePrefix] for contextual help matching.
Widget helpButton(BuildContext context, {String? routePrefix}) {
  return IconButton(
    icon: const Icon(Icons.help_outline),
    tooltip: 'Help',
    onPressed: () => showHelpForRoute(context, routePrefix),
  );
}

/// Navigates to the appropriate help screen based on the route prefix.
void showHelpForRoute(BuildContext context, String? routePrefix) {
  if (routePrefix == null || routePrefix.isEmpty) {
    context.push('/profile/help');
    return;
  }

  final matching = allHelpArticles
      .where((a) =>
          a.relatedRoutePrefix != null &&
          a.relatedRoutePrefix == routePrefix)
      .toList();

  if (matching.length == 1) {
    context.push('/profile/help/${matching.first.id}');
    return;
  }

  // Find the best category match
  final categoryMatches = allHelpArticles
      .where((a) =>
          a.relatedRoutePrefix != null &&
          (routePrefix.startsWith(a.relatedRoutePrefix!) ||
           a.relatedRoutePrefix!.startsWith(routePrefix)))
      .toList();

  if (categoryMatches.isNotEmpty) {
    final category = categoryMatches.first.category;
    context.push('/profile/help?category=${category.name}');
  } else {
    context.push('/profile/help');
  }
}

/// Maps route prefixes to HelpCategory for contextual matching.
HelpCategory? categoryForRoute(String? routePrefix) {
  if (routePrefix == null) return null;
  if (routePrefix.startsWith('/dashboard')) return HelpCategory.dashboard;
  if (routePrefix.startsWith('/trips')) return HelpCategory.trips;
  if (routePrefix.startsWith('/visits')) return HelpCategory.visits;
  if (routePrefix.startsWith('/explore')) return HelpCategory.explore;
  if (routePrefix.startsWith('/profile')) return HelpCategory.profile;
  return null;
}
