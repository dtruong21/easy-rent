import 'package:easyrent/features/auth/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoginPage smoke test', () {
    testWidgets('renders without crash and shows key text', (WidgetTester tester) async {
      // LoginPage is a plain StatelessWidget with zero Supabase dependency —
      // safe to mount in isolation inside a bare MaterialApp.
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginPage(),
        ),
      );

      // The page must build a Scaffold with the app title visible.
      expect(find.text('EasyRent'), findsOneWidget);

      // The connection prompt must be present (French locale requirement).
      expect(
        find.text('Connectez-vous pour gérer vos locations'),
        findsOneWidget,
      );
    });
  });
}
