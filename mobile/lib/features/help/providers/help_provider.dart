import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/help_content.dart';
import '../models/help_article.dart';

final helpArticlesProvider =
    Provider<List<HelpArticle>>((_) => allHelpArticles);

final helpSearchQueryProvider = StateProvider<String>((_) => '');

final helpCategoryFilterProvider = StateProvider<HelpCategory?>((_) => null);

final filteredHelpArticlesProvider = Provider<List<HelpArticle>>((ref) {
  final articles = ref.watch(helpArticlesProvider);
  final query = ref.watch(helpSearchQueryProvider).toLowerCase();
  final category = ref.watch(helpCategoryFilterProvider);

  var result = articles;
  if (category != null) {
    result = result.where((a) => a.category == category).toList();
  }
  if (query.isNotEmpty) {
    result = result
        .where((a) =>
            a.title.toLowerCase().contains(query) ||
            a.keywords.any((k) => k.contains(query)) ||
            a.sections.any((s) => s.body.toLowerCase().contains(query)))
        .toList();
  }
  return result;
});

final helpArticleByIdProvider =
    Provider.family<HelpArticle?, String>((ref, id) {
  return ref
      .watch(helpArticlesProvider)
      .where((a) => a.id == id)
      .firstOrNull;
});

final helpArticlesForRouteProvider =
    Provider.family<List<HelpArticle>, String>((ref, routePrefix) {
  return ref
      .watch(helpArticlesProvider)
      .where((a) =>
          a.relatedRoutePrefix != null &&
          routePrefix.startsWith(a.relatedRoutePrefix!))
      .toList();
});
