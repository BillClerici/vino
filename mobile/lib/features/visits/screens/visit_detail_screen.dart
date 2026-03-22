import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/visit.dart';
import '../../../core/widgets/rating_stars.dart';
import '../providers/visits_provider.dart';

class VisitDetailScreen extends ConsumerWidget {
  final String visitId;
  const VisitDetailScreen({super.key, required this.visitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitState = ref.watch(visitDetailProvider(visitId));

    return visitState.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (visit) => _VisitDetailBody(visit: visit),
    );
  }
}

class _VisitDetailBody extends StatelessWidget {
  final VisitLog visit;
  const _VisitDetailBody({required this.visit});

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:${dt.minute.toString().padLeft(2, '0')} $amPm';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final wines = visit.winesTasted ?? [];
    final hasRatings = visit.ratingOverall != null;
    final favCount = wines.where((w) => w.isFavorite).length;
    final ratedWines = wines.where((w) => w.rating != null).toList();
    final avgWineRating = ratedWines.isNotEmpty
        ? ratedWines.map((w) => w.rating!).reduce((a, b) => a + b) / ratedWines.length
        : null;
    final purchasedWines = wines.where((w) => w.purchased).toList();
    final photosCount = wines.where((w) => w.photo.isNotEmpty).length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero Header ──
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (visit.place?.imageUrl.isNotEmpty == true)
                    Image.network(visit.place!.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _gradientBg(colorScheme))
                  else
                    _gradientBg(colorScheme),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20, right: 20, bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(visit.place?.name ?? 'Visit',
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                            const SizedBox(width: 6),
                            Text(_formatDate(visit.visitedAt),
                                style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            if (_formatTime(visit.visitedAt).isNotEmpty) ...[
                              const SizedBox(width: 12),
                              const Icon(Icons.access_time, size: 14, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(_formatTime(visit.visitedAt),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ],
                        ),
                        if (visit.place?.city?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.place, size: 14, color: Colors.white70),
                                const SizedBox(width: 6),
                                Text('${visit.place!.city}, ${visit.place?.state ?? ''}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Quick Stats Row ──
                  Row(
                    children: [
                      _StatBadge(
                        value: '${wines.length}',
                        label: 'Tastings',
                        icon: Icons.wine_bar,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      if (hasRatings)
                        _StatBadge(
                          value: '${visit.ratingOverall}/5',
                          label: 'Overall',
                          icon: Icons.star,
                          color: Colors.amber,
                        ),
                      if (hasRatings) const SizedBox(width: 8),
                      _StatBadge(
                        value: '$favCount',
                        label: 'Favorites',
                        icon: Icons.favorite,
                        color: Colors.red,
                      ),
                      if (purchasedWines.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _StatBadge(
                          value: '${purchasedWines.length}',
                          label: 'Bought',
                          icon: Icons.shopping_bag,
                          color: Colors.green,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Experience Ratings ──
                  if (hasRatings) ...[
                    Text('Experience', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _RatingBar(label: 'Overall', rating: visit.ratingOverall, color: Colors.amber),
                            _RatingBar(label: 'Staff', rating: visit.ratingStaff, color: colorScheme.primary),
                            _RatingBar(label: 'Ambience', rating: visit.ratingAmbience, color: colorScheme.secondary),
                            _RatingBar(label: 'Food & Drink', rating: visit.ratingFood, color: colorScheme.tertiary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Notes ──
                  if (visit.notes.isNotEmpty) ...[
                    Card(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.format_quote, size: 20, color: Colors.grey[400]),
                            const SizedBox(width: 8),
                            Expanded(child: Text(visit.notes, style: const TextStyle(fontSize: 14))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Wine Photos Gallery ──
                  if (photosCount > 0) ...[
                    Text('Photos', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 100,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: wines
                            .where((w) => w.photo.isNotEmpty)
                            .map((w) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      w.photo,
                                      width: 100, height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 100, height: 100,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.broken_image),
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── Wines Tasted ──
                  if (wines.isNotEmpty) ...[
                    Row(
                      children: [
                        Text('Tastings (${wines.length})', style: Theme.of(context).textTheme.titleMedium),
                        if (avgWineRating != null) ...[
                          const Spacer(),
                          Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text('Avg ${avgWineRating.toStringAsFixed(1)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...wines.map((wine) => _WineDetailCard(wine: wine)),
                  ],

                  // ── Empty state ──
                  if (wines.isEmpty && !hasRatings)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.wine_bar, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text('No tastings or ratings recorded',
                                style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientBg(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, const Color(0xFF5DADE2)],
        ),
      ),
    );
  }
}

// ── Stat Badge ──────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  const _StatBadge({required this.value, required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey[200]!),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
              Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rating Bar (visual bar instead of stars) ────────────────────

class _RatingBar extends StatelessWidget {
  final String label;
  final int? rating;
  final Color color;
  const _RatingBar({required this.label, required this.rating, required this.color});

  @override
  Widget build(BuildContext context) {
    if (rating == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: rating! / 5.0,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$rating/5',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ── Wine Detail Card (rich) ─────────────────────────────────────

class _WineDetailCard extends StatelessWidget {
  final VisitWine wine;
  const _WineDetailCard({required this.wine});

  Color _typeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('red') || t.contains('cab') || t.contains('merlot') || t.contains('pinot noir')) {
      return const Color(0xFF8E1A3C);
    }
    if (t.contains('white') || t.contains('chard') || t.contains('riesling') || t.contains('sauvignon blanc')) {
      return const Color(0xFFD4A843);
    }
    if (t.contains('rosé') || t.contains('rose')) {
      return const Color(0xFFE8A0BF);
    }
    if (t.contains('ipa') || t.contains('lager') || t.contains('stout') || t.contains('ale')) {
      return Colors.orange;
    }
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    final name = wine.displayName.isNotEmpty ? wine.displayName : wine.wineName;
    final colorScheme = Theme.of(context).colorScheme;
    final typeColor = _typeColor(wine.wineType);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo or color dot
            if (wine.photo.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(wine.photo,
                    width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _wineDot(typeColor)),
              )
            else
              _wineDot(typeColor),
            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      if (wine.isFavorite)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.favorite, size: 16, color: Colors.red),
                        ),
                      if (wine.purchased)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.shopping_bag, size: 16, color: Colors.green[700]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Type + Serving
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(wine.wineType.isNotEmpty ? wine.wineType : 'Other',
                            style: TextStyle(fontSize: 10, color: typeColor, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      if (wine.servingType.isNotEmpty)
                        Text(_formatServing(wine.servingType),
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      if (wine.wineVintage != null)
                        Text(' · ${wine.wineVintage}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  // Rating
                  if (wine.rating != null) ...[
                    const SizedBox(height: 4),
                    RatingStars(rating: wine.rating, size: 14),
                  ],
                  // Tasting notes
                  if (wine.tastingNotes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(wine.tastingNotes,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                  ],
                  // Rating comments
                  if (wine.ratingComments.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(wine.ratingComments,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wineDot(Color color) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(Icons.wine_bar, size: 24, color: color),
      ),
    );
  }

  String _formatServing(String serving) {
    return serving
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }
}
