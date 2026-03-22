import 'package:flutter/material.dart';
import '../models/place.dart';
import 'rating_stars.dart';

class PlaceCard extends StatelessWidget {
  final Place place;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;
  final VoidCallback? onStartTrip;

  const PlaceCard({
    super.key,
    required this.place,
    this.onTap,
    this.onFavorite,
    this.onStartTrip,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (place.imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  place.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.storefront, size: 48),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          place.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onFavorite != null)
                        IconButton(
                          icon: Icon(
                            place.isFavorited
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: place.isFavorited ? Colors.red : null,
                          ),
                          onPressed: onFavorite,
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      if (onStartTrip != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.map,
                              color: Theme.of(context).colorScheme.primary),
                          onPressed: onStartTrip,
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Start Trip',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    place.location,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (place.avgRating != null) ...[
                        RatingStars(rating: place.avgRating!.round(), size: 14),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${place.visitCount} visits',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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
