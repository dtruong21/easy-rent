/// Tests widget pour [CardEmptyState].
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/cards/card_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  );
}

void main() {
  group('CardEmptyState — affichage', () {
    testWidgets('affiche icon + title + message', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CardEmptyState(
            icon: Icons.home_outlined,
            title: 'Aucun bien',
            message: 'Ajoutez votre premier bien.',
          ),
        ),
      );
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.text('Aucun bien'), findsOneWidget);
      expect(find.text('Ajoutez votre premier bien.'), findsOneWidget);
    });

    testWidgets('sans action → pas de widget action', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CardEmptyState(
            icon: Icons.people_outline,
            title: 'Aucun locataire',
            message: 'Aucun locataire pour le moment.',
          ),
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('avec action FilledButton → bouton visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CardEmptyState(
            icon: Icons.home_outlined,
            title: 'Aucun bien',
            message: 'Ajoutez un bien.',
            action: FilledButton(
              onPressed: () {},
              child: const Text('Ajouter'),
            ),
          ),
        ),
      );
      expect(find.text('Ajouter'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('action onPressed → callback appelé', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        _wrap(
          CardEmptyState(
            icon: Icons.home_outlined,
            title: 'Titre',
            message: 'Message.',
            action: FilledButton(
              onPressed: () => pressed = true,
              child: const Text('Cliquer'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Cliquer'));
      await tester.pump();
      expect(pressed, isTrue);
    });
  });

  group('CardEmptyState — centrage', () {
    testWidgets('est centré via Center', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CardEmptyState(
            icon: Icons.info_outline,
            title: 'Titre',
            message: 'Message.',
          ),
        ),
      );
      expect(find.byType(Center), findsWidgets);
    });
  });
}
