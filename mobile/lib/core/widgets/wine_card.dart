import 'package:flutter/material.dart';
import '../models/visit.dart';
import 'rating_stars.dart';

class WineCard extends StatelessWidget {
  final VisitWine wine;
  final VoidCallback? onTap;

  const WineCard({super.key, required this.wine, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.local_drink),
        ),
        title: Text(
          wine.displayName.isNotEmpty ? wine.displayName : wine.wineName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wine.wineType.isNotEmpty)
              Text('${wine.wineType} - ${wine.servingType}'),
            if (wine.rating != null) RatingStars(rating: wine.rating, size: 14),
          ],
        ),
        trailing: wine.isFavorite
            ? const Icon(Icons.favorite, color: Colors.red, size: 18)
            : null,
      ),
    );
  }
}
