/// Tests widget pour [CardGrid].
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/cards/card_grid.dart';
import 'package:easyrent/core/ui/cards/status_pill.dart';
import 'package:easyrent/core/ui/cards/status_pill_tone.dart';
import 'package:easyrent/core/ui/cards/summary_card.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {double width = 1024}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SizedBox(width: width, child: child),
    ),
  );
}

List<Widget> _buildItems(int count) {
  return List.generate(
    count,
    (i) => SizedBox(key: ValueKey('item_$i'), child: Text('Item $i')),
  );
}

void main() {
  group('CardGrid — constructeur standard', () {
    testWidgets('liste vide — pas d\'erreur', (tester) async {
      await tester.pumpWidget(_wrap(CardGrid(children: const [])));
      expect(find.byType(CardGrid), findsOneWidget);
    });

    testWidgets('3 items — affiche 3 éléments', (tester) async {
      await tester.pumpWidget(
        _wrap(CardGrid(shrinkWrap: true, children: _buildItems(3))),
      );
      await tester.pump();
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
    });
  });

  group('CardGrid.builder — virtualisation', () {
    testWidgets('builder avec 5 items — affiche des éléments visibles', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CardGrid.builder(
            shrinkWrap: true,
            itemCount: 5,
            itemBuilder: (context, i) => Text('Builder $i'),
          ),
        ),
      );
      await tester.pump();
      // Au moins le premier item est visible.
      expect(find.text('Builder 0'), findsOneWidget);
    });

    testWidgets('builder itemCount=0 — pas d\'erreur', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CardGrid.builder(
            shrinkWrap: true,
            itemCount: 0,
            itemBuilder: (context, i) => Text('Item $i'),
          ),
        ),
      );
      expect(find.byType(CardGrid), findsOneWidget);
    });
  });

  group('CardGrid — largeurs responsives', () {
    for (final width in [320.0, 390.0]) {
      testWidgets('largeur $width — colonne unique en liste', (tester) async {
        await tester.pumpWidget(
          _wrap(
            CardGrid(shrinkWrap: true, children: _buildItems(3)),
            width: width,
          ),
        );
        await tester.pump();
        expect(find.byType(GridView), findsNothing);
        expect(find.byType(ListView), findsOneWidget);
      });
    }
    for (final width in [600.0, 1024.0, 1440.0]) {
      testWidgets('largeur $width — grille', (tester) async {
        await tester.pumpWidget(
          _wrap(
            CardGrid(shrinkWrap: true, children: _buildItems(3)),
            width: width,
          ),
        );
        await tester.pump();
        expect(find.byType(GridView), findsOneWidget);
      });
    }
  });

  group('CardGrid — hauteur des cartes', () {
    Widget card(int i) =>
        SizedBox(key: ValueKey('card_$i'), height: 120, child: Text('Card $i'));

    testWidgets('mobile : hauteur naturelle, mainAxisExtent ignoré', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CardGrid(
            shrinkWrap: true,
            mainAxisExtent: 220,
            children: [card(0), card(1)],
          ),
          width: 390,
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('card_0'))).height, 120);
    });

    testWidgets('desktop : hauteur fixe mainAxisExtent', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CardGrid(
            shrinkWrap: true,
            mainAxisExtent: 220,
            children: [card(0), card(1)],
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('card_0'))).height, 220);
    });
  });

  group('CardGrid — gap et padding', () {
    testWidgets('gap personnalisé — accepté sans erreur', (tester) async {
      await tester.pumpWidget(
        _wrap(CardGrid(gap: 24, shrinkWrap: true, children: _buildItems(2))),
      );
      expect(find.byType(CardGrid), findsOneWidget);
    });

    testWidgets('padding personnalisé — accepté sans erreur', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CardGrid(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: _buildItems(2),
          ),
        ),
      );
      expect(find.byType(CardGrid), findsOneWidget);
    });
  });

  // Pire cas FEAT-059 (#198) : une carte « chiffre clé » complète (sous-titre,
  // statut, info, action rapide) dans une cellule calibrée à 124 px, avec un
  // grand texte d'accessibilité. Sans mise à l'échelle de la cellule, le
  // contenu dépasse la hauteur fixe et Flutter signale un débordement.
  group('CardGrid — grande taille de texte (desktop)', () {
    Widget fullCard(int i) => SummaryCard(
      title: 'Appartement T3 Lyon $i',
      subtitle: 'Marie Martin',
      keyFigure: const SummaryKeyFigure(
        value: '850,00 €',
        caption: 'CC / mois',
      ),
      status: const StatusPill(
        label: 'Loué',
        tone: StatusPillTone.success,
        icon: Icons.check,
        size: StatusPillSize.sm,
      ),
      meta: 'Depuis 01/01/2024',
      quickAction: SummaryQuickActionButton(
        icon: Icons.call_outlined,
        label: 'Appeler',
        onPressed: () {},
      ),
      menuItems: [SummaryMenuItem(label: 'Modifier', onSelected: () {})],
    );

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('échelle de texte $scale : aucune carte ne déborde', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(1400, 1000),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: CardGrid(
                  mainAxisExtent: 124,
                  children: List.generate(4, fullCard),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(SummaryCard), findsWidgets);
      });
    }
  });
}
