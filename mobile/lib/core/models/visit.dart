import 'place.dart';

class VisitLog {
  final String id;
  final Place? place;
  final String visitedAt;
  final String notes;
  final int? ratingStaff;
  final int? ratingAmbience;
  final int? ratingFood;
  final int? ratingOverall;
  final int winesCount;
  final List<VisitWine>? winesTasted;

  const VisitLog({
    required this.id,
    this.place,
    required this.visitedAt,
    this.notes = '',
    this.ratingStaff,
    this.ratingAmbience,
    this.ratingFood,
    this.ratingOverall,
    this.winesCount = 0,
    this.winesTasted,
  });

  factory VisitLog.fromJson(Map<String, dynamic> json) {
    return VisitLog(
      id: json['id'] as String,
      place: json['place'] != null
          ? Place.fromJson(json['place'] as Map<String, dynamic>)
          : null,
      visitedAt: json['visited_at'] as String,
      notes: json['notes'] as String? ?? '',
      ratingStaff: json['rating_staff'] as int?,
      ratingAmbience: json['rating_ambience'] as int?,
      ratingFood: json['rating_food'] as int?,
      ratingOverall: json['rating_overall'] as int?,
      winesCount: json['wines_count'] as int? ?? 0,
      winesTasted: (json['wines_tasted'] as List<dynamic>?)
          ?.map((e) => VisitWine.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class VisitWine {
  final String id;
  final String? menuItem;
  final String? menuItemName;
  final String wineName;
  final String wineType;
  final int? wineVintage;
  final String servingType;
  final int quantity;
  final bool isFavorite;
  final String tastingNotes;
  final int? rating;
  final String ratingComments;
  final String photo;
  final bool purchased;
  final String displayName;

  const VisitWine({
    required this.id,
    this.menuItem,
    this.menuItemName,
    this.wineName = '',
    this.wineType = '',
    this.wineVintage,
    this.servingType = 'tasting',
    this.quantity = 1,
    this.isFavorite = false,
    this.tastingNotes = '',
    this.rating,
    this.ratingComments = '',
    this.photo = '',
    this.purchased = false,
    this.displayName = '',
  });

  factory VisitWine.fromJson(Map<String, dynamic> json) {
    return VisitWine(
      id: json['id'] as String,
      menuItem: json['menu_item'] as String?,
      menuItemName: json['menu_item_name'] as String?,
      wineName: json['wine_name'] as String? ?? '',
      wineType: json['wine_type'] as String? ?? '',
      wineVintage: json['wine_vintage'] as int?,
      servingType: json['serving_type'] as String? ?? 'tasting',
      quantity: json['quantity'] as int? ?? 1,
      isFavorite: json['is_favorite'] as bool? ?? false,
      tastingNotes: json['tasting_notes'] as String? ?? '',
      rating: json['rating'] as int?,
      ratingComments: json['rating_comments'] as String? ?? '',
      photo: json['photo'] as String? ?? '',
      purchased: json['purchased'] as bool? ?? false,
      displayName: json['display_name'] as String? ?? '',
    );
  }
}
