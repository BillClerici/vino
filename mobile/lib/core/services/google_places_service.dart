import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../config/env.dart';

class GooglePlacesService {
  final _dio = Dio();

  /// Search for places using Google Places API (New) Text Search.
  Future<List<Map<String, dynamic>>> textSearch(String query,
      {String? type}) async {
    final apiKey = EnvConfig.googleMapsApiKey;
    if (apiKey.isEmpty) {
      debugPrint('[GooglePlaces] No API key configured');
      return [];
    }

    try {
      // Use Places API (New) Text Search
      final resp = await _dio.post(
        'https://places.googleapis.com/v1/places:searchText',
        data: {
          'textQuery': '$query ${type ?? ""}',
          'maxResultCount': 20,
        },
        options: Options(headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask':
              'places.id,places.displayName,places.formattedAddress,places.location,places.types,places.websiteUri,places.nationalPhoneNumber,places.photos',
        }),
      );

      final places = resp.data['places'] as List<dynamic>? ?? [];
      return places.map((p) => _mapPlace(p as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[GooglePlaces] Text search error: $e');
      // Fallback to legacy Places API
      return _legacyTextSearch(query, type: type);
    }
  }

  /// Search for nearby places when the map moves.
  Future<List<Map<String, dynamic>>> nearbySearch({
    required double lat,
    required double lng,
    required double radiusMeters,
    String? type,
  }) async {
    final apiKey = EnvConfig.googleMapsApiKey;
    if (apiKey.isEmpty) return [];

    try {
      final resp = await _dio.post(
        'https://places.googleapis.com/v1/places:searchNearby',
        data: {
          'includedTypes': _googleTypes(type),
          'maxResultCount': 20,
          'locationRestriction': {
            'circle': {
              'center': {'latitude': lat, 'longitude': lng},
              'radius': radiusMeters,
            }
          },
        },
        options: Options(headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask':
              'places.id,places.displayName,places.formattedAddress,places.location,places.types,places.websiteUri,places.nationalPhoneNumber,places.photos',
        }),
      );

      final places = resp.data['places'] as List<dynamic>? ?? [];
      return places.map((p) => _mapPlace(p as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[GooglePlaces] Nearby search error: $e');
      return [];
    }
  }

  /// Fallback: Legacy Places API text search
  Future<List<Map<String, dynamic>>> _legacyTextSearch(String query,
      {String? type}) async {
    final apiKey = EnvConfig.googleMapsApiKey;
    try {
      final typeParam = type == 'brewery' ? 'bar' : type == 'restaurant' ? 'restaurant' : '';
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/textsearch/json',
        queryParameters: {
          'query': '$query ${type ?? "winery"}',
          'key': apiKey,
          if (typeParam.isNotEmpty) 'type': typeParam,
        },
      );
      final results = resp.data['results'] as List<dynamic>? ?? [];
      return results
          .map((r) => _mapLegacyPlace(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[GooglePlaces] Legacy search error: $e');
      return [];
    }
  }

  List<String> _googleTypes(String? placeType) {
    switch (placeType) {
      case 'brewery':
        return ['bar', 'brewery'];
      case 'restaurant':
        return ['restaurant'];
      default: // winery
        return ['winery'];
    }
  }

  Map<String, dynamic> _mapPlace(Map<String, dynamic> p) {
    final loc = p['location'] as Map<String, dynamic>? ?? {};
    final name = p['displayName'] as Map<String, dynamic>? ?? {};
    final address = p['formattedAddress'] as String? ?? '';
    // Parse city/state from formatted address
    final parts = address.split(', ');

    return {
      'google_place_id': p['id'] ?? '',
      'name': name['text'] ?? '',
      'address': address,
      'city': parts.length >= 3 ? parts[parts.length - 3] : '',
      'state': parts.length >= 2
          ? parts[parts.length - 2].replaceAll(RegExp(r'\s*\d{5}.*'), '')
          : '',
      'latitude': loc['latitude'],
      'longitude': loc['longitude'],
      'website': p['websiteUri'] ?? '',
      'phone': p['nationalPhoneNumber'] ?? '',
      'photos': p['photos'] ?? [],
      'source': 'google',
    };
  }

  Map<String, dynamic> _mapLegacyPlace(Map<String, dynamic> r) {
    final loc = r['geometry']?['location'] as Map<String, dynamic>? ?? {};
    final address = r['formatted_address'] as String? ?? '';
    final parts = address.split(', ');

    return {
      'google_place_id': r['place_id'] ?? '',
      'name': r['name'] ?? '',
      'address': address,
      'city': parts.length >= 3 ? parts[parts.length - 3] : '',
      'state': parts.length >= 2
          ? parts[parts.length - 2].replaceAll(RegExp(r'\s*\d{5}.*'), '')
          : '',
      'latitude': loc['lat'],
      'longitude': loc['lng'],
      'website': '',
      'phone': '',
      'source': 'google',
    };
  }
}
