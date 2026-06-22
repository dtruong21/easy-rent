/// Tests widget pour [CardGrid].
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/cards/card_grid.dart';
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
    for (final width in [320.0, 600.0, 1024.0, 1440.0]) {
      testWidgets('largeur $width — rendu sans erreur', (tester) async {
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
}
