class Place {
  final String id;
  final String name;
  final String placeType;
  final String description;
  final String address;
  final String city;
  final String state;
  final String zipCode;
  final String country;
  final double? latitude;
  final double? longitude;
  final String website;
  final String phone;
  final String imageUrl;
  final int visitCount;
  final double? avgRating;
  final bool isFavorited;
  final List<MenuItem>? menuItems;

  const Place({
    required this.id,
    required this.name,
    this.placeType = 'winery',
    this.description = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.zipCode = '',
    this.country = 'US',
    this.latitude,
    this.longitude,
    this.website = '',
    this.phone = '',
    this.imageUrl = '',
    this.visitCount = 0,
    this.avgRating,
    this.isFavorited = false,
    this.menuItems,
  });

  String get location => [city, state].where((s) => s.isNotEmpty).join(', ');

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] as String,
      name: json['name'] as String,
      placeType: json['place_type'] as String? ?? 'winery',
      description: json['description'] as String? ?? '',
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zipCode: json['zip_code'] as String? ?? '',
      country: json['country'] as String? ?? 'US',
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      website: json['website'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      visitCount: json['visit_count'] as int? ?? 0,
      avgRating: _toDouble(json['avg_rating']),
      isFavorited: json['is_favorited'] as bool? ?? false,
      menuItems: (json['menu_items'] as List<dynamic>?)
          ?.map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MenuItem {
  final String id;
  final String name;
  final String varietal;
  final int? vintage;
  final String description;
  final double? price;
  final String imageUrl;

  const MenuItem({
    required this.id,
    required this.name,
    this.varietal = '',
    this.vintage,
    this.description = '',
    this.price,
    this.imageUrl = '',
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as String,
      name: json['name'] as String,
      varietal: json['varietal'] as String? ?? '',
      vintage: json['vintage'] as int?,
      description: json['description'] as String? ?? '',
      price: _toDouble(json['price']),
      imageUrl: json['image_url'] as String? ?? '',
    );
  }
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
