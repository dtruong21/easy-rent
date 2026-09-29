/// Tests widget de [SummaryCard] (cartes de liste « chiffre clé »).
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/cards/summary_card.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {double width = 360}) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('fr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  testWidgets('titre, sous-titre, chiffre clé et légende affichés', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SummaryCard(
          title: 'Studio Test',
          subtitle: 'Marie Locataire',
          keyFigure: SummaryKeyFigure(value: '800,00 €', caption: 'CC / mois'),
          meta: '12 rue des Lilas',
        ),
      ),
    );
    expect(find.text('Studio Test'), findsOneWidget);
    expect(find.text('Marie Locataire'), findsOneWidget);
    expect(find.text('800,00 €'), findsOneWidget);
    expect(find.text('CC / mois'), findsOneWidget);
    expect(find.text('12 rue des Lilas'), findsOneWidget);
  });

  testWidgets('tap carte, tap action rapide et menu sont isolés', (
    tester,
  ) async {
    var cardTaps = 0;
    var actionTaps = 0;
    var menuTaps = 0;
    await tester.pumpWidget(
      _wrap(
        SummaryCard(
          title: 'Bail',
          keyFigure: const SummaryKeyFigure(value: '800,00 €'),
          onTap: () => cardTaps++,
          quickAction: SummaryQuickActionButton(
            key: const Key('qa'),
            icon: Icons.add,
            label: 'Paiement',
            onPressed: () => actionTaps++,
          ),
          menuKey: const Key('menu'),
          menuItems: [
            SummaryMenuItem(
              key: const Key('item_edit'),
              label: 'Modifier',
              onSelected: () => menuTaps++,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('qa')));
    await tester.pump();
    expect((cardTaps, actionTaps), (0, 1));

    await tester.tap(find.byKey(const Key('menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item_edit')));
    await tester.pumpAndSettle();
    expect((cardTaps, menuTaps), (0, 1));

    await tester.tap(find.text('Bail'));
    await tester.pump();
    expect(cardTaps, 1);
  });

  testWidgets('action rapide et menu ⋮ respectent la cible tactile Android', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(
        SummaryCard(
          title: 'Bail',
          keyFigure: const SummaryKeyFigure(value: '800,00 €'),
          onTap: () {},
          quickAction: SummaryQuickActionButton(
            key: const Key('qa'),
            icon: Icons.add,
            label: 'Paiement',
            onPressed: () {},
          ),
          menuKey: const Key('menu'),
          menuItems: [SummaryMenuItem(label: 'Modifier', onSelected: () {})],
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('sans chiffre clé : action rapide en haut à droite', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SummaryCard(
          title: 'T2 Bastille',
          subtitle: 'Aucun locataire',
          quickAction: SummaryQuickActionButton(
            key: const Key('qa'),
            icon: Icons.add,
            label: 'Créer un bail',
            onPressed: () {},
          ),
        ),
      ),
    );
    final titleY = tester.getCenter(find.text('T2 Bastille')).dy;
    final actionY = tester.getCenter(find.byKey(const Key('qa'))).dy;
    expect((actionY - titleY).abs(), lessThan(16));
  });

  testWidgets('item destructive rendu en couleur error', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SummaryCard(
          title: 'Quittance',
          menuKey: const Key('menu'),
          menuItems: [
            SummaryMenuItem(
              label: 'Annuler',
              onSelected: () {},
              destructive: true,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('menu')));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('Annuler'));
    final ctx = tester.element(find.text('Annuler'));
    expect(text.style?.color, Theme.of(ctx).colorScheme.error);
  });

  testWidgets('aucun menu ⋮ quand menuItems est vide', (tester) async {
    await tester.pumpWidget(_wrap(const SummaryCard(title: 'X')));
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('320 px, textes longs : aucun débordement', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SummaryCard(
          title: 'Appartement très long nom de résidence principale Paris',
          subtitle: 'Locataire au nom particulièrement long vraiment',
          keyFigure: const SummaryKeyFigure(
            value: '12 345,67 €',
            caption: 'CC / mois',
          ),
          status: const Chip(label: Text('En retard')),
          meta: '128 boulevard du Montparnasse, 75014 Paris · Appartement',
          quickAction: SummaryQuickActionButton(
            icon: Icons.add,
            label: 'Paiement',
            onPressed: () {},
          ),
          menuItems: [SummaryMenuItem(label: 'Modifier', onSelected: () {})],
        ),
        width: 320,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
