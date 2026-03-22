import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

String? authGuard(BuildContext context, WidgetRef ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return '/login';
      return null; // Allow access
    },
    loading: () => null,
    error: (_, __) => '/login',
  );
}
