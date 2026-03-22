import 'package:flutter/material.dart';

import '../models/help_article.dart';

class HelpArticleCard extends StatelessWidget {
  final HelpArticle article;
  final VoidCallback onTap;
  const HelpArticleCard({super.key, required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(article.icon, size: 20, color: cs.onPrimaryContainer),
        ),
        title: Text(article.title,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(article.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
