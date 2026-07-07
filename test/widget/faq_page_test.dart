/// Tests widget de [FaqPage] — page publique `/faq`.
///
/// Couvre : rendu des questions (repliées par défaut), dépliage d'une
/// réponse au tap, présence des sujets sensibles (suppression de compte,
/// conformité quittances) et renvoi vers le support.
library;

import 'package:easyrent/features/support/presentation/faq_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _buildPage() {
  final router = GoRouter(
    initialLocation: '/faq',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('landing-stub')),
      ),
      GoRoute(path: '/faq', builder: (context, state) => const FaqPage()),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  testWidgets('titre + questions affichées, réponses repliées par défaut', (
    tester,
  ) async {
    await tester.pumpWidget(_buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Questions fréquentes'), findsOneWidget);
    expect(find.text('FAQ — Baillan'), findsOneWidget);
    expect(find.text('Qu\'est-ce que Baillan ?'), findsOneWidget);
    expect(find.byKey(const Key('faq_tile_0')), findsOneWidget);

    // Replié par défaut : le corps de la première réponse n'est pas visible.
    expect(
      find.textContaining('outil de gestion locative', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('tap sur une question → la réponse se déplie', (tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Qu\'est-ce que Baillan ?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('outil de gestion locative'), findsOneWidget);
  });

  testWidgets(
    'sujets clés présents : suppression de compte, quittances loi 1989, '
    'données/RGPD, contact support',
    (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      expect(
        find.text('Comment supprimer mon compte et mes données ?'),
        findsOneWidget,
      );
      expect(
        find.text('Les quittances générées sont-elles conformes à la loi ?'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Comment contacter le support ?'),
        200,
      );
      expect(find.text('Comment contacter le support ?'), findsOneWidget);
      expect(
        find.text('Où sont stockées mes données et celles de mes locataires ?'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'la réponse suppression mentionne la rétention légale des quittances '
    '(cohérence FEAT-045)',
    (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      // Index 8 dans _faqEntries = « Comment supprimer mon compte … ».
      final deleteTile = find.byKey(const Key('faq_tile_8'));
      await tester.ensureVisible(deleteTile);
      await tester.pumpAndSettle();
      await tester.tap(deleteTile);
      await tester.pumpAndSettle();

      expect(find.textContaining('conservées 5 ans'), findsOneWidget);
      expect(find.textContaining('/delete-account'), findsOneWidget);
    },
  );
}
