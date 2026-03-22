import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/trip_service.dart';
import '../../../core/widgets/rating_stars.dart';
import '../providers/places_provider.dart';

class PlaceDetailScreen extends ConsumerWidget {
  final String placeId;
  const PlaceDetailScreen({super.key, required this.placeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeState = ref.watch(placeDetailProvider(placeId));

    return Scaffold(
      appBar: AppBar(title: const Text('Place Details')),
      body: placeState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (place) => ListView(
          children: [
            if (place.imageUrl.isNotEmpty)
              Image.network(
                place.imageUrl,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(height: 200),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.name,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    '${place.placeType.toUpperCase()} - ${place.location}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (place.avgRating != null)
                        RatingStars(rating: place.avgRating!.round()),
                      const SizedBox(width: 16),
                      Text('${place.visitCount} visits'),
                    ],
                  ),
                  if (place.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(place.description),
                  ],
                  const SizedBox(height: 16),
                  if (place.address.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(place.address),
                      contentPadding: EdgeInsets.zero,
                    ),
                  if (place.phone.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: Text(place.phone),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => launchUrl(Uri.parse('tel:${place.phone}')),
                    ),
                  if (place.website.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.language),
                      title: Text(place.website),
                      contentPadding: EdgeInsets.zero,
                      onTap: () => launchUrl(Uri.parse(place.website)),
                    ),
                  const SizedBox(height: 24),
                  if (place.menuItems != null &&
                      place.menuItems!.isNotEmpty) ...[
                    Text('Wine Menu',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...place.menuItems!.map((item) => ListTile(
                          leading: const Icon(Icons.local_drink),
                          title: Text(item.name),
                          subtitle: Text([
                            item.varietal,
                            if (item.vintage != null) '${item.vintage}',
                          ].join(' - ')),
                          trailing: item.price != null
                              ? Text('\$${item.price!.toStringAsFixed(2)}')
                              : null,
                          contentPadding: EdgeInsets.zero,
                        )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: placeState.maybeWhen(
        data: (place) => FloatingActionButton.extended(
          onPressed: () => startTripFromPlace(
            context: context,
            ref: ref,
            placeId: place.id,
            placeName: place.name,
          ),
          icon: const Icon(Icons.map),
          label: const Text('Start Trip'),
        ),
        orElse: () => null,
      ),
    );
  }
}
