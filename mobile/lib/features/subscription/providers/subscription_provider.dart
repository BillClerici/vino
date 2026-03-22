import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';

final subscriptionStatusProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiClientProvider);
  final resp = await api.get(ApiPaths.subscriptionStatus);
  return resp.data['data'] as Map<String, dynamic>;
});
