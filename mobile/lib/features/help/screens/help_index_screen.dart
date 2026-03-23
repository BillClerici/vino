import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../onboarding/onboarding_tour.dart';

import '../../../core/widgets/search_bar.dart';
import '../models/help_article.dart';
import '../providers/help_provider.dart';
import '../widgets/help_article_card.dart';

class HelpIndexScreen extends ConsumerStatefulWidget {
  final HelpCategory? initialCategory;
  const HelpIndexScreen({super.key, this.initialCategory});

  @override
  ConsumerState<HelpIndexScreen> createState() => _HelpIndexScreenState();
}

class _HelpIndexScreenState extends ConsumerState<HelpIndexScreen>
    with TickerProviderStateMixin {
  late final TabController _tabCtl;
  String _searchQuery = '';

  static const _categories = HelpCategory.values;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialCategory != null
        ? _categories.indexOf(widget.initialCategory!)
        : 0;
    _tabCtl = TabController(
      length: _categories.length,
      vsync: this,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
    );
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allArticles = ref.watch(helpArticlesProvider);
    final cs = Theme.of(context).colorScheme;

    // Filter by search query
    final searchResults = _searchQuery.isEmpty
        ? null
        : allArticles
            .where((a) =>
                a.title.toLowerCase().contains(_searchQuery) ||
                a.keywords.any((k) => k.contains(_searchQuery)) ||
                a.sections
                    .any((s) => s.body.toLowerCase().contains(_searchQuery)))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Guide'),
        bottom: _searchQuery.isEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(kTextTabBarHeight),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                    },
                  ),
                  child: TabBar(
                    controller: _tabCtl,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: _categories
                        .map((c) => Tab(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(c.icon, size: 16),
                                  const SizedBox(width: 6),
                                  Text(c.label),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          // Take the Tour card
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: ListTile(
                leading: Icon(Icons.tour, color: Theme.of(context).colorScheme.primary),
                title: const Text('Take the Guided Tour', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Quick walkthrough of all features', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward),
                dense: true,
                onTap: () => showOnboardingTour(context, ref),
              ),
            ),
          ),
          VinoSearchBar(
            hint: 'Search help articles...',
            onChanged: (q) => setState(() => _searchQuery = q.toLowerCase()),
          ),
          Expanded(
            child: searchResults != null
                ? _buildSearchResults(searchResults)
                : TabBarView(
                    controller: _tabCtl,
                    children: _categories.map((cat) {
                      final articles = allArticles
                          .where((a) => a.category == cat)
                          .toList();
                      return _buildArticleList(articles, cat, cs);
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(List<HelpArticle> results) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            const Text('No matching articles found'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: results.length,
      itemBuilder: (_, i) => HelpArticleCard(
        article: results[i],
        onTap: () => context.push('/profile/help/${results[i].id}'),
      ),
    );
  }

  Widget _buildArticleList(
      List<HelpArticle> articles, HelpCategory cat, ColorScheme cs) {
    if (articles.isEmpty) {
      return const Center(child: Text('No articles in this category'));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: articles.length,
      itemBuilder: (_, i) => HelpArticleCard(
        article: articles[i],
        onTap: () => context.push('/profile/help/${articles[i].id}'),
      ),
    );
  }
}
