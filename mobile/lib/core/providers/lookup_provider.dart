import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/constants.dart';
import '../api/api_client.dart';
import '../models/lookup_value.dart';

/// Fetches lookup values by parent code, cached per code.
final lookupProvider =
    FutureProvider.family<List<LookupValue>, String>((ref, parentCode) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(
    ApiPaths.lookups,
    queryParameters: {'parent_code': parentCode, 'page_size': '100'},
  );
  final data = resp.data['data'] as List<dynamic>;
  return data
      .map((e) => LookupValue.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Returns the correct lookup codes based on place type.
class DrinkLookupCodes {
  final String typeCode;
  final String servingCode;

  const DrinkLookupCodes({required this.typeCode, required this.servingCode});

  /// Maps place_type to the appropriate lookup parent codes.
  factory DrinkLookupCodes.forPlaceType(String placeType) {
    switch (placeType) {
      case 'brewery':
        return const DrinkLookupCodes(
          typeCode: 'BEER_TYPE',
          servingCode: 'BEER_SERVING',
        );
      default: // winery, restaurant, other
        return const DrinkLookupCodes(
          typeCode: 'WINE_TYPE',
          servingCode: 'WINE_SERVING',
        );
    }
  }
}
