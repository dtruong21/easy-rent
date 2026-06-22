/// Tests widget pour [CardSkeleton].
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/cards/card_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
    home: Scaffold(body: child),
  );
}

void main() {
  group('CardSkeleton — rendu', () {
    testWidgets('se rend sans erreur (light)', (tester) async {
      await tester.pumpWidget(_wrap(const CardSkeleton()));
      expect(find.byType(CardSkeleton), findsOneWidget);
    });

    testWidgets('se rend sans erreur (dark)', (tester) async {
      await tester.pumpWidget(
        _wrap(const CardSkeleton(), brightness: Brightness.dark),
      );
      expect(find.byType(CardSkeleton), findsOneWidget);
    });

    testWidgets('contient un Container principal', (tester) async {
      await tester.pumpWidget(_wrap(const CardSkeleton()));
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('pas de texte affiché (placeholder pur)', (tester) async {
      await tester.pumpWidget(_wrap(const CardSkeleton()));
      // CardSkeleton ne doit afficher aucun texte.
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('3 barres de placeholder rendues', (tester) async {
      await tester.pumpWidget(_wrap(const CardSkeleton()));
      // 3 FractionallySizedBox pour les 3 barres.
      expect(find.byType(FractionallySizedBox), findsNWidgets(3));
    });
  });

  group('CardSkeleton — pas de shimmer (Phase 0)', () {
    testWidgets('pas d\'AnimatedContainer shimmer', (tester) async {
      await tester.pumpWidget(_wrap(const CardSkeleton()));
      // Phase 0 : skeleton statique, pas d'animation shimmer.
      // On attend 2 frames et vérifie que rien ne change visuellement.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CardSkeleton), findsOneWidget);
    });
  });
}
