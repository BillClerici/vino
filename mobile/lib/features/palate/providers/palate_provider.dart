import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/palate_profile.dart';

final palateProvider = FutureProvider<PalateData>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiPaths.palate);
  return PalateData.fromJson(resp.data['data'] as Map<String, dynamic>);
});
