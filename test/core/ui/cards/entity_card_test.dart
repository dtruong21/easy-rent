/// Tests widget pour [EntityCard].
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/cards/entity_card.dart';
import 'package:easyrent/core/ui/cards/entity_card_density.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
    home: Scaffold(body: child),
  );
}

void main() {
  group('EntityCard — affichage', () {
    testWidgets('affiche le header', (tester) async {
      await tester.pumpWidget(
        _wrap(EntityCard(header: const Text('Mon titre'))),
      );
      expect(find.text('Mon titre'), findsOneWidget);
    });

    testWidgets('affiche header + body + footer', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EntityCard(
            header: const Text('Header'),
            body: const Text('Body'),
            footer: const Text('Footer'),
          ),
        ),
      );
      expect(find.text('Header'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
      expect(find.text('Footer'), findsOneWidget);
    });

    testWidgets('sans footer → pas de footer rendu', (tester) async {
      await tester.pumpWidget(_wrap(EntityCard(header: const Text('Header'))));
      expect(find.text('Footer'), findsNothing);
    });
  });

  group('EntityCard — onTap', () {
    testWidgets('onTap null → pas de ripple', (tester) async {
      await tester.pumpWidget(
        _wrap(EntityCard(header: const Text('Sans tap'))),
      );
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('onTap fourni → InkWell présent', (tester) async {
      await tester.pumpWidget(
        _wrap(EntityCard(onTap: () {}, header: const Text('Avec tap'))),
      );
      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('onTap fourni → callback appelé', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          EntityCard(
            onTap: () => tapped = true,
            header: const Text('Tappable'),
          ),
        ),
      );
      await tester.tap(find.byType(EntityCard));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('EntityCard — density', () {
    testWidgets('density compact — card se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EntityCard(
            density: EntityCardDensity.compact,
            header: const Text('Compact'),
          ),
        ),
      );
      expect(find.byType(EntityCard), findsOneWidget);
      expect(find.text('Compact'), findsOneWidget);
    });

    testWidgets('density standard — card se rend sans erreur', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EntityCard(
            density: EntityCardDensity.standard,
            header: const Text('Standard'),
          ),
        ),
      );
      expect(find.byType(EntityCard), findsOneWidget);
    });
  });

  group('EntityCard — semanticLabel', () {
    testWidgets('semanticLabel: widget Semantics présent dans l\'arbre', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          EntityCard(
            onTap: () {},
            semanticLabel: 'Bail Dupont',
            header: const Text('Header'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Vérifie que le widget Semantics est bien présent dans l'arbre.
      expect(find.byType(Semantics), findsWidgets);
      // Vérifie que le texte du header reste visible.
      expect(find.text('Header'), findsOneWidget);
    });
  });

  group('EntityCard — footer non-propagation', () {
    testWidgets(
      'tap FilledButton dans footer n\'appelle pas onTap de la carte',
      (tester) async {
        var cardTapped = false;
        var buttonTapped = false;

        await tester.pumpWidget(
          _wrap(
            EntityCard(
              onTap: () => cardTapped = true,
              header: const Text('Header'),
              footer: FilledButton(
                onPressed: () => buttonTapped = true,
                child: const Text('Action'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Action'));
        await tester.pump();

        expect(buttonTapped, isTrue);
        // Le tap sur le bouton NE doit PAS déclencher onTap de la carte.
        expect(cardTapped, isFalse);
      },
    );
  });

  group('EntityCard — dark mode', () {
    testWidgets('se rend sans erreur en dark mode', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EntityCard(header: const Text('Dark mode')),
          brightness: Brightness.dark,
        ),
      );
      expect(find.text('Dark mode'), findsOneWidget);
    });
  });
}
