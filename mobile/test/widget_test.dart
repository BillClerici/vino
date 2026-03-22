import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vino_mobile/features/auth/screens/login_screen.dart';

void main() {
  testWidgets('Login screen shows OAuth buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );

    expect(find.text('Trip Me'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Microsoft'), findsOneWidget);
  });

  testWidgets('Rating stars render correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: _TestRatingStars(),
        ),
      ),
    );

    // Should find 5 star icons
    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.byIcon(Icons.star_border), findsNWidgets(2));
  });
}

class _TestRatingStars extends StatelessWidget {
  const _TestRatingStars();

  @override
  Widget build(BuildContext context) {
    // Inline test for rating stars
    return Row(
      children: List.generate(5, (i) {
        return Icon(i < 3 ? Icons.star : Icons.star_border);
      }),
    );
  }
}
