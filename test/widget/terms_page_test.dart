/// Tests widget de [TermsPage].
///
/// Couvre :
/// - Titre et sections clés affichés
/// - Renvoi vers la politique de confidentialité
library;

import 'package:easyrent/features/privacy/presentation/terms_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _buildPage() {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, _) => const TermsPage()),
      GoRoute(
        path: '/privacy',
        builder: (context, _) => const Scaffold(body: Text('page privacy')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  group('TermsPage', () {
    testWidgets('titre et sections clés affichés', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      // AppBar + corps de page.
      expect(find.text("Conditions générales d'utilisation"), findsWidgets);
      expect(find.text('1. Objet'), findsOneWidget);
      expect(find.text('4. Documents générés'), findsOneWidget);
      expect(find.text('10. Droit applicable'), findsOneWidget);
    });

    testWidgets('bouton vers la politique de confidentialité navigue', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('btn_terms_to_privacy')));
      await tester.tap(find.byKey(const Key('btn_terms_to_privacy')));
      await tester.pumpAndSettle();

      expect(find.text('page privacy'), findsOneWidget);
    });
  });
}
