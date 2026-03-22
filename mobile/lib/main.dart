import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config/env.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvConfig.loadRemoteConfig();
  runApp(
    const ProviderScope(
      child: VinoApp(),
    ),
  );
}
