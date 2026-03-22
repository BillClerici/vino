import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/help_provider.dart';
import '../widgets/help_section_widget.dart';

class HelpArticleScreen extends ConsumerWidget {
  final String articleId;
  const HelpArticleScreen({super.key, required this.articleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final article = ref.watch(helpArticleByIdProvider(articleId));

    if (article == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Help')),
        body: const Center(child: Text('Article not found')),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(article.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Category badge
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(article.category.icon,
                        size: 14, color: cs.onPrimaryContainer),
                    const SizedBox(width: 4),
                    Text(article.category.label,
                        style: TextStyle(
                            fontSize: 12, color: cs.onPrimaryContainer)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Sections
          ...article.sections.map((s) => HelpSectionWidget(section: s)),
        ],
      ),
    );
  }
}
