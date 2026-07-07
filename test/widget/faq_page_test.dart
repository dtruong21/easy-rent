/// Tests widget de [FaqPage] — page publique `/faq`.
///
/// Couvre : sections thématiques, questions repliées par défaut, dépliage
/// d'une réponse au tap, présence des sujets sensibles (suppression de
/// compte cohérente FEAT-045, conformité quittances) et renvoi support.
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
  testWidgets('titre + sections thématiques affichés', (tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Questions fréquentes'), findsOneWidget);
    expect(find.text('FAQ — Baillan'), findsOneWidget);
    expect(find.text('Découvrir Baillan'), findsOneWidget);
    // Les autres sections existent plus bas dans le scroll (layout complet
    // en test, même hors viewport).
    expect(find.text('Loyers, paiements et quittances'), findsOneWidget);
    expect(find.text('Charges et dépenses'), findsOneWidget);
    expect(find.text('Données, sécurité et RGPD'), findsOneWidget);
    expect(find.text('Compte et support'), findsOneWidget);
  });

  testWidgets('questions repliées par défaut, dépliage au tap', (tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('faq_tile_quoi')), findsOneWidget);
    // Replié : le corps de la réponse n'est pas monté.
    expect(find.textContaining('registre locatif'), findsNothing);

    await tester.tap(find.text('Qu\'est-ce que Baillan ?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('registre locatif'), findsOneWidget);
  });

  testWidgets(
    'sujets clés présents : quittances loi 1989, retards, régularisation, '
    'RGPD, support',
    (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      expect(
        find.text('Les quittances sont-elles conformes à la loi ?'),
        findsOneWidget,
      );
      expect(
        find.text('Comment Baillan détecte-t-il les retards de paiement ?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Comment fonctionne la régularisation annuelle des charges ?',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Qui est responsable des données de mes locataires (RGPD) ?'),
        findsOneWidget,
      );
      expect(find.text('Comment contacter le support ?'), findsOneWidget);
    },
  );

  testWidgets(
    'la réponse suppression mentionne la rétention légale des quittances '
    '(cohérence FEAT-045)',
    (tester) async {
      await tester.pumpWidget(_buildPage());
      await tester.pumpAndSettle();

      final deleteTile = find.byKey(const Key('faq_tile_suppression-compte'));
      await tester.ensureVisible(deleteTile);
      await tester.pumpAndSettle();
      await tester.tap(deleteTile);
      await tester.pumpAndSettle();

      expect(find.textContaining('conservées 5 ans'), findsOneWidget);
      expect(find.textContaining('/delete-account'), findsOneWidget);
    },
  );

  testWidgets('les features non livrées sont « à l\'étude », jamais promises '
      '(rappels, import)', (tester) async {
    await tester.pumpWidget(_buildPage());
    await tester.pumpAndSettle();

    final remindersTile = find.byKey(const Key('faq_tile_rappels'));
    await tester.ensureVisible(remindersTile);
    await tester.pumpAndSettle();
    await tester.tap(remindersTile);
    await tester.pumpAndSettle();

    expect(find.textContaining('Pas encore'), findsOneWidget);
    expect(find.textContaining('à l\'étude'), findsOneWidget);
  });
}
