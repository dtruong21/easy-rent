/// Tests widget de [LegalPage] — mentions légales LCEN.
///
/// Couvre :
/// - Titre + sections clés (éditeur, hébergeur) affichés
/// - Bandeau « brouillon » tant que les placeholders subsistent
/// - Renvoi vers la politique de confidentialité
library;

import 'package:easyrent/features/privacy/presentation/legal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _buildPage() {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, _) => const LegalPage()),
      GoRoute(
        path: '/privacy',
        builder: (context, _) => const Scaffold(body: Text('page privacy')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  group('LegalPage', () {
    testWidgets('titre + sections éditeur/hébergeur affichés', (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Mentions légales'), findsWidgets); // AppBar + header
      expect(find.text('1. Éditeur du service'), findsOneWidget);
      expect(find.text('3. Hébergeur'), findsOneWidget);
      // L'hébergeur est factuel (Firebase/Google), pas un placeholder.
      expect(find.textContaining('Google Ireland'), findsOneWidget);
    });

    testWidgets('bandeau brouillon présent tant que placeholders à compléter', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('box_legal_placeholder_warning')),
        findsOneWidget,
      );
      expect(find.textContaining('à compléter'), findsWidgets);
    });

    testWidgets('bouton vers la politique de confidentialité navigue', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('btn_legal_to_privacy')));
      await tester.tap(find.byKey(const Key('btn_legal_to_privacy')));
      await tester.pumpAndSettle();

      expect(find.text('page privacy'), findsOneWidget);
    });
  });
}
