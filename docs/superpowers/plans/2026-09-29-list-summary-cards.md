# Cartes de liste « chiffre clé » + puces de filtre — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer les cartes `EntityCard` des 4 listes (biens, baux, locataires, quittances) par une carte compacte « chiffre clé » (`SummaryCard`) avec 1 action rapide + menu ⋮, et les filtres par des puces avec compteurs (`FilterChipsBar`), sur toutes les largeurs.

**Architecture:** Deux widgets de présentation purs dans `lib/core/ui/` (`SummaryCard`, `FilterChipsBar<T>`), sans import de feature. Chaque carte de feature devient un adaptateur « entité → `SummaryCard` » qui réutilise les destinations, callbacks et libellés existants. Les compteurs de filtres sont dérivés côté client des listes déjà chargées, via un prédicat extrait (aucun changement de comportement du filtrage).

**Tech Stack:** Flutter 3.44, Riverpod (`StateProvider`/`Provider`), go_router, url_launcher, gen_l10n (FR + EN).

**Spec :** `docs/superpowers/specs/2026-09-29-mobile-list-cards-design.md`

## Global Constraints

- Carte : liseré gauche **4 px** couleur du bien (`PropertyColorKey.resolveColor`), gris `outlineVariant` sans couleur ; padding **12 px** ; écart **6 px** entre la rangée haute et la rangée basse ; chiffre clé **17 px / w700**, légende **11 px** `onSurfaceVariant`.
- **1 seule action rapide visible** par carte ; le reste dans le menu ⋮. Tap carte = fiche (quittance : ouvre le PDF).
- Puces : `ChoiceChip`, défilement horizontal, puce active couleur `primary`, compteur après le libellé ; pas de compteur pendant le chargement.
- **Partout** : mêmes cartes et puces sur mobile, tablette, desktop. La vue tableau desktop (`ViewMode.table` hors quittances) ne change pas.
- Aucune nouvelle logique métier : chaque action reprend la route/callback existante (listée par tâche).
- l10n : toute nouvelle clé dans `lib/l10n/app_en.arb` (template) **et** `lib/l10n/app_fr.arb`, avec entrée `@clé` descriptive en EN.
- Fichiers générés (`*.freezed.dart`, `*.g.dart`, `app_localizations*.dart`) : gitignorés, **jamais commités** ; régénérer avec `flutter gen-l10n` après modification des ARB.
- Commits : `git add` avec chemins explicites, jamais `git add -A`. Fin de message : `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Avant chaque commit : `export PATH=/opt/homebrew/bin:$PATH`, `dart format` sur les fichiers touchés, `flutter analyze` sans issue, tests de la tâche verts. Ne pas lancer `dart format .` (le checkout `build/ios/SourcePackages` est en lecture seule).

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `lib/core/ui/cards/summary_card.dart` (créé) | `SummaryCard`, `SummaryKeyFigure`, `SummaryMenuItem`, `SummaryQuickActionButton` |
| `lib/core/ui/filters/filter_chips_bar.dart` (créé) | `FilterChipsBar<T>`, `FilterChipOption<T>` |
| `lib/features/properties/…` | `PropertyListItem.currentRentCcCents`, `PropertyCard` adaptateur, `propertyMatchesFilter` + `propertyFilterCountsProvider`, `PropertiesFilterBar` en puces |
| `lib/features/leases/…` | `LeaseCard` adaptateur, `leaseMatchesFilter` + `leaseFilterCountsProvider`, `LeasesFilterBar` en puces |
| `lib/features/tenants/…` | `TenantListItem.activeLeaseChargesCents`, `TenantCard` adaptateur (Appeler / email), `tenantMatchesFilter` + `tenantFilterCountsProvider`, `TenantsFilterBar` en puces |
| `lib/features/receipts/…` | `ReceiptCard` adaptateur, timeline mobile sur `ReceiptCard`, `receiptMatchesStatus` + `receiptStatusCountsProvider`, `ReceiptsFilterBar` en puces |
| `android/app/src/main/AndroidManifest.xml` | intent `DIAL` / `tel` dans `<queries>` |

---

### Task 1: `SummaryCard` (widget partagé)

**Files:**
- Create: `lib/core/ui/cards/summary_card.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb` (clé `commonMoreActions`)
- Test: `test/core/ui/cards/summary_card_test.dart`

**Interfaces:**
- Produces:
  - `class SummaryKeyFigure { const SummaryKeyFigure({required String value, String? caption}); }`
  - `class SummaryMenuItem { const SummaryMenuItem({required String label, required VoidCallback onSelected, bool destructive = false, Key? key}); }`
  - `class SummaryQuickActionButton extends StatelessWidget { const SummaryQuickActionButton({super.key, required IconData icon, required String label, required VoidCallback? onPressed, String? tooltip}); }`
  - `class SummaryCard extends StatelessWidget { const SummaryCard({super.key, required String title, String? subtitle, Color? accentColor, SummaryKeyFigure? keyFigure, Widget? status, String? meta, Widget? quickAction, List<SummaryMenuItem> menuItems = const [], Key? menuKey, VoidCallback? onTap, String? semanticLabel}); }`
  - l10n : `context.l10n.commonMoreActions` (« More actions » / « Plus d'actions »).
  - Règle de placement : avec `keyFigure` → action rapide dans la rangée basse ; sans `keyFigure` → action rapide en haut à droite.

- [ ] **Step 1: Ajouter la clé l10n**

Dans `lib/l10n/app_en.arb`, à côté de `"commonEdit"` :

```json
  "commonMoreActions": "More actions",
  "@commonMoreActions": { "description": "Tooltip of the ⋮ overflow menu on list cards" },
```

Dans `lib/l10n/app_fr.arb`, à côté de `"commonEdit"` :

```json
  "commonMoreActions": "Plus d'actions",
```

Run: `flutter gen-l10n` — Expected: génération sans erreur.

- [ ] **Step 2: Écrire le test qui échoue**

`test/core/ui/cards/summary_card_test.dart` :

```dart
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
    body: Center(child: SizedBox(width: width, child: child)),
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
            SummaryMenuItem(label: 'Annuler', onSelected: () {}, destructive: true),
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
          keyFigure: const SummaryKeyFigure(value: '12 345,67 €', caption: 'CC / mois'),
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
```

- [ ] **Step 3: Lancer le test — il échoue**

Run: `flutter test test/core/ui/cards/summary_card_test.dart`
Expected: FAIL — `summary_card.dart` introuvable.

- [ ] **Step 4: Implémenter**

`lib/core/ui/cards/summary_card.dart` :

```dart
import 'package:flutter/material.dart';

import '../../i18n/l10n_extensions.dart';

/// Chiffre clé affiché en gros à droite d'une [SummaryCard].
class SummaryKeyFigure {
  const SummaryKeyFigure({required this.value, this.caption});

  /// Valeur formatée (ex. « 800,00 € »).
  final String value;

  /// Légende sous la valeur (ex. « CC / mois »).
  final String? caption;
}

/// Entrée du menu ⋮ d'une [SummaryCard].
class SummaryMenuItem {
  const SummaryMenuItem({
    required this.label,
    required this.onSelected,
    this.destructive = false,
    this.key,
  });

  final String label;
  final VoidCallback onSelected;

  /// Action destructive (ex. annuler une quittance) : texte couleur `error`.
  final bool destructive;

  /// Clé posée sur le `PopupMenuItem` (tests).
  final Key? key;
}

/// Bouton compact de l'action rapide d'une [SummaryCard].
///
/// Une seule action rapide par carte : la plus fréquente pour l'entité.
/// `onPressed == null` → bouton désactivé (le [tooltip] explique pourquoi).
class SummaryQuickActionButton extends StatelessWidget {
  const SummaryQuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
        textStyle: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Carte de liste « chiffre clé » (spec 2026-09-29).
///
/// ```
/// ┌▌ Titre                      800 €  ⋮ ┐
/// │▌ Sous-titre                CC / mois │
/// └▌ [statut]  info           [Action]   ┘
/// ```
///
/// Présentation pure : aucun import de feature. Les adaptateurs de chaque
/// feature (`PropertyCard`, `LeaseCard`, …) lui passent des chaînes déjà
/// localisées et des callbacks existants.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    this.subtitle,
    this.accentColor,
    this.keyFigure,
    this.status,
    this.meta,
    this.quickAction,
    this.menuItems = const [],
    this.menuKey,
    this.onTap,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;

  /// Couleur du liseré gauche (couleur du bien). `null` → `outlineVariant`.
  final Color? accentColor;

  /// Chiffre clé en haut à droite. Absent → l'action rapide prend sa place.
  final SummaryKeyFigure? keyFigure;

  /// Pastille de statut (typiquement un `StatusPill` taille sm).
  final Widget? status;

  /// Information secondaire de la rangée basse (1 ligne, ellipsis).
  final String? meta;

  /// Action rapide (typiquement un [SummaryQuickActionButton]).
  final Widget? quickAction;

  /// Entrées du menu ⋮ — menu masqué si vide.
  final List<SummaryMenuItem> menuItems;

  /// Clé du bouton ⋮ (tests).
  final Key? menuKey;

  final VoidCallback? onTap;
  final String? semanticLabel;

  static const double _accentWidth = 4;
  static const double _padding = 12;
  static const double _rowGap = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(12);

    final hasKeyFigure = keyFigure != null;
    final topAction = hasKeyFigure ? null : quickAction;
    final bottomAction = hasKeyFigure ? quickAction : null;
    final hasBottomRow =
        status != null || (meta?.isNotEmpty ?? false) || bottomAction != null;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        _padding + _accentWidth,
        _padding - 2,
        _padding - 4,
        _padding - 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (hasKeyFigure) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      keyFigure!.value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (keyFigure!.caption != null)
                      Text(
                        keyFigure!.caption!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
              if (topAction != null) ...[
                const SizedBox(width: 8),
                Flexible(child: topAction),
              ],
              if (menuItems.isNotEmpty) _buildMenu(context),
            ],
          ),
          if (hasBottomRow) ...[
            const SizedBox(height: _rowGap),
            Row(
              children: [
                if (status != null) ...[status!, const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    meta ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (bottomAction != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: bottomAction),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Material(
        color: colors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              content,
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _accentWidth,
                child: ColoredBox(color: accentColor ?? colors.outlineVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return PopupMenuButton<int>(
      key: menuKey,
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: context.l10n.commonMoreActions,
      style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
      onSelected: (i) => menuItems[i].onSelected(),
      itemBuilder: (_) => [
        for (var i = 0; i < menuItems.length; i++)
          PopupMenuItem<int>(
            key: menuItems[i].key,
            value: i,
            child: Text(
              menuItems[i].label,
              style: menuItems[i].destructive ? TextStyle(color: error) : null,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 5: Lancer le test — il passe**

Run: `flutter test test/core/ui/cards/summary_card_test.dart`
Expected: PASS (6 tests). Si « aucun débordement » échoue, corriger le layout (ne pas affaiblir le test).

- [ ] **Step 6: Commit**

```bash
dart format lib/core/ui/cards/summary_card.dart test/core/ui/cards/summary_card_test.dart
flutter analyze lib/core/ui/cards test/core/ui/cards
git add lib/core/ui/cards/summary_card.dart test/core/ui/cards/summary_card_test.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb
git commit -m "feat(ui): SummaryCard — carte de liste « chiffre clé »"
```

---

### Task 2: `FilterChipsBar<T>` (widget partagé)

**Files:**
- Create: `lib/core/ui/filters/filter_chips_bar.dart`
- Test: `test/core/ui/filters/filter_chips_bar_test.dart`

**Interfaces:**
- Produces:
  - `class FilterChipOption<T> { const FilterChipOption({required T value, required String label, int? count}); }`
  - `class FilterChipsBar<T> extends StatelessWidget { const FilterChipsBar({super.key, required List<FilterChipOption<T>> options, required T selected, required ValueChanged<T> onSelected, Widget? trailing}); }`
  - Chaque puce a la clé `Key('filter_chip_$value')` (`value.toString()`, ex. `filter_chip_PropertyFilter.vacant`).

- [ ] **Step 1: Écrire le test qui échoue**

`test/core/ui/filters/filter_chips_bar_test.dart` :

```dart
/// Tests widget de [FilterChipsBar].
library;

import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/filters/filter_chips_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _F { all, a, b, c, d }

Widget _wrap(Widget child, {double width = 390}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: SizedBox(width: width, child: child)),
);

void main() {
  testWidgets('libellés et compteurs affichés, puce active sélectionnée', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        FilterChipsBar<_F>(
          options: const [
            FilterChipOption(value: _F.all, label: 'Tous', count: 3),
            FilterChipOption(value: _F.a, label: 'Loués', count: 1),
          ],
          selected: _F.all,
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.textContaining('Tous'), findsOneWidget);
    expect(find.textContaining('3'), findsOneWidget);
    final all = tester.widget<ChoiceChip>(find.byKey(Key('filter_chip_${_F.all}')));
    final a = tester.widget<ChoiceChip>(find.byKey(Key('filter_chip_${_F.a}')));
    expect(all.selected, isTrue);
    expect(a.selected, isFalse);
  });

  testWidgets('sans compteur (chargement) : libellé seul', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FilterChipsBar<_F>(
          options: const [FilterChipOption(value: _F.all, label: 'Tous')],
          selected: _F.all,
          onSelected: (_) {},
        ),
      ),
    );
    expect(find.text('Tous'), findsOneWidget);
  });

  testWidgets('tap sur une puce → onSelected(valeur)', (tester) async {
    _F? picked;
    await tester.pumpWidget(
      _wrap(
        FilterChipsBar<_F>(
          options: const [
            FilterChipOption(value: _F.all, label: 'Tous'),
            FilterChipOption(value: _F.b, label: 'Vacants'),
          ],
          selected: _F.all,
          onSelected: (v) => picked = v,
        ),
      ),
    );
    await tester.tap(find.byKey(Key('filter_chip_${_F.b}')));
    expect(picked, _F.b);
  });

  testWidgets('5 puces à 320 px + trailing : aucun débordement', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        FilterChipsBar<_F>(
          options: const [
            FilterChipOption(value: _F.all, label: 'Tous', count: 12),
            FilterChipOption(value: _F.a, label: 'Actifs', count: 8),
            FilterChipOption(value: _F.b, label: 'À renouveler', count: 2),
            FilterChipOption(value: _F.c, label: 'En retard', count: 1),
            FilterChipOption(value: _F.d, label: 'Terminés', count: 1),
          ],
          selected: _F.all,
          onSelected: (_) {},
          trailing: const Icon(Icons.grid_view),
        ),
        width: 320,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
  });
}
```

- [ ] **Step 2: Lancer — échec**

Run: `flutter test test/core/ui/filters/filter_chips_bar_test.dart`
Expected: FAIL — fichier introuvable.

- [ ] **Step 3: Implémenter**

`lib/core/ui/filters/filter_chips_bar.dart` :

```dart
import 'package:flutter/material.dart';

/// Option d'une [FilterChipsBar].
class FilterChipOption<T> {
  const FilterChipOption({required this.value, required this.label, this.count});

  final T value;
  final String label;

  /// Nombre d'éléments correspondant au filtre. `null` → pas de compteur
  /// (liste encore en chargement).
  final int? count;
}

/// Rangée de puces de filtre avec compteurs (spec 2026-09-29, D4).
///
/// Défile horizontalement quand les puces dépassent la largeur. [trailing]
/// (ex. `ViewModeToggle` sur desktop, sélecteur d'année des quittances)
/// reste fixe à droite.
class FilterChipsBar<T> extends StatelessWidget {
  const FilterChipsBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.trailing,
  });

  final List<FilterChipOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in options)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _chip(option, colors),
                  ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }

  Widget _chip(FilterChipOption<T> option, ColorScheme colors) {
    final isSelected = option.value == selected;
    final fg = isSelected ? colors.onPrimary : colors.onSurface;
    return ChoiceChip(
      key: Key('filter_chip_${option.value}'),
      selected: isSelected,
      showCheckmark: false,
      selectedColor: colors.primary,
      onSelected: (_) => onSelected(option.value),
      label: Text.rich(
        TextSpan(
          text: option.label,
          style: TextStyle(color: fg),
          children: [
            if (option.count != null)
              TextSpan(
                text: '  ${option.count}',
                style: TextStyle(color: fg.withValues(alpha: 0.7)),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Lancer — succès**

Run: `flutter test test/core/ui/filters/filter_chips_bar_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
dart format lib/core/ui/filters test/core/ui/filters
flutter analyze lib/core/ui/filters test/core/ui/filters
git add lib/core/ui/filters/filter_chips_bar.dart test/core/ui/filters/filter_chips_bar_test.dart
git commit -m "feat(ui): FilterChipsBar — puces de filtre avec compteurs"
```

---

### Task 3: Biens — carte + puces

**Files:**
- Modify: `lib/features/properties/domain/property_list_item.dart` (champ `currentRentCcCents`)
- Modify: `lib/features/properties/data/property_repository.dart:160-185` (renseigner le champ)
- Modify: `lib/features/properties/application/properties_filter_provider.dart` (prédicat + compteurs)
- Modify: `lib/features/properties/presentation/widgets/property_card.dart` (réécriture adaptateur)
- Modify: `lib/features/properties/presentation/widgets/properties_filter_bar.dart` (puces)
- Modify: `lib/features/properties/presentation/widgets/properties_card_view.dart` (`mainAxisExtent: 220` → `124`, 2 occurrences)
- Test: `test/widget/property_card_test.dart` (créé), `test/unit/properties_filter_counts_test.dart` (créé), mettre à jour `test/widget/properties_card_view_test.dart`, `test/widget/properties_filter_bar_test.dart`

**Interfaces:**
- Consumes: `SummaryCard`, `SummaryKeyFigure`, `SummaryMenuItem`, `SummaryQuickActionButton` (Task 1) ; `FilterChipsBar`, `FilterChipOption` (Task 2).
- Produces:
  - `PropertyListItem.currentRentCcCents` (`int?`, loyer + charges du bail actif).
  - `bool propertyMatchesFilter(PropertyListItem item, PropertyFilter filter)`
  - `final propertyFilterCountsProvider = Provider<Map<PropertyFilter, int>?>` (`null` tant que la liste charge).

Correspondance (spec §4) :
- Loué : sous-titre = `currentTenantName`, chiffre clé = `MoneyFormat.formatEurosFromCents(currentRentCcCents)` + légende = nouvelle clé `commonRentCcPerMonthCaption` (« CC / mois » / « incl. charges / month »). Pas d'action rapide. Menu : `propertiesViewLease` → `context.push('/leases/$activeLeaseId')` (clé `card_view_lease_$propertyId`), `commonEdit` → `context.push('/properties/$propertyId/edit')` (clé `card_edit_property_$propertyId`).
- Vacant : sous-titre = `l10n.propertiesNoTenant`, pas de chiffre clé, action rapide `+ propertiesCreateLease` → `context.push('/leases/new?propertyId=$propertyId')` (clé `card_create_lease_$propertyId`). Menu : `commonEdit` seul.
- Statut : `StatusPill` depuis `propertyOccupancyPill(item, context)` (taille `sm`). Meta : `'${property.address} · ${property.type.label(context)}$surfaceSuffix'` (même `surfaceSuffix` qu'aujourd'hui).
- Liseré : `PropertyColorKey.resolve(entityId: property.id, stored: property.colorKey).resolveColor(context)`.
- `semanticLabel` : `l10n.propertiesCardSemanticLabel(property.name, pillData.label)` (inchangé).

- [ ] **Step 1: Clé l10n de légende**

`app_en.arb` : `"commonRentCcPerMonthCaption": "incl. charges / month",` + `"@commonRentCcPerMonthCaption": {"description": "Caption under the monthly rent (rent + charges) key figure on list cards"},`
`app_fr.arb` : `"commonRentCcPerMonthCaption": "CC / mois",`
Run: `flutter gen-l10n`.

- [ ] **Step 2: Tests qui échouent**

`test/unit/properties_filter_counts_test.dart` :

```dart
import 'package:easyrent/features/properties/application/properties_filter_provider.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_filter.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:flutter_test/flutter_test.dart';

PropertyListItem _item(String id, {String? leaseId}) => PropertyListItem(
  property: Property(
    id: id,
    landlordId: 'l1',
    name: 'Bien $id',
    address: '1 rue X',
    type: PropertyType.appartement,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  activeLeaseId: leaseId,
);

void main() {
  test('propertyMatchesFilter : loués / vacants / tous', () {
    final loue = _item('a', leaseId: 'L1');
    final vacant = _item('b');
    expect(propertyMatchesFilter(loue, PropertyFilter.occupied), isTrue);
    expect(propertyMatchesFilter(vacant, PropertyFilter.occupied), isFalse);
    expect(propertyMatchesFilter(vacant, PropertyFilter.vacant), isTrue);
    expect(propertyMatchesFilter(loue, PropertyFilter.all), isTrue);
  });

  test('propertyFilterCounts compte chaque filtre', () {
    final counts = propertyFilterCounts([
      _item('a', leaseId: 'L1'),
      _item('b'),
      _item('c'),
    ]);
    expect(counts, {
      PropertyFilter.all: 3,
      PropertyFilter.occupied: 1,
      PropertyFilter.vacant: 2,
    });
  });
}
```

(Si le constructeur de `Property` exige d'autres champs requis, les renseigner en lisant `lib/features/properties/domain/property.dart`.)

`test/widget/property_card_test.dart` — rendu loué vs vacant et navigation :

```dart
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/widgets/property_card.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

PropertyListItem _item({String? leaseId}) => PropertyListItem(
  property: Property(
    id: 'p1',
    landlordId: 'l1',
    name: 'Studio Test',
    address: '12 rue des Lilas',
    type: PropertyType.appartement,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  activeLeaseId: leaseId,
  currentTenantName: leaseId == null ? null : 'Marie Locataire',
  currentRentCcCents: leaseId == null ? null : 80000,
);

Widget _app(PropertyListItem item) => MaterialApp.router(
  theme: AppTheme.light,
  locale: const Locale('fr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: supportedLocales,
  routerConfig: GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            Scaffold(body: PropertyCard(item: item, onTap: () {})),
      ),
      GoRoute(path: '/leases/new', builder: (_, _) => const Text('new lease')),
      GoRoute(path: '/leases/:id', builder: (_, s) => Text('lease ${s.pathParameters['id']}')),
      GoRoute(path: '/properties/:id/edit', builder: (_, _) => const Text('edit')),
    ],
  ),
);

void main() {
  testWidgets('loué : loyer en chiffre clé, pas d\'action rapide', (t) async {
    await t.pumpWidget(_app(_item(leaseId: 'L1')));
    await t.pumpAndSettle();
    expect(find.text('Marie Locataire'), findsOneWidget);
    expect(find.textContaining('800,00'), findsOneWidget);
    expect(find.text('CC / mois'), findsOneWidget);
    expect(find.byKey(const Key('card_create_lease_p1')), findsNothing);
  });

  testWidgets('loué : menu ⋮ → Voir le bail', (t) async {
    await t.pumpWidget(_app(_item(leaseId: 'L1')));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('card_view_lease_p1')));
    await t.pumpAndSettle();
    expect(find.text('lease L1'), findsOneWidget);
  });

  testWidgets('vacant : action rapide Créer un bail', (t) async {
    await t.pumpWidget(_app(_item()));
    await t.pumpAndSettle();
    expect(find.text('Aucun locataire'), findsOneWidget);
    await t.tap(find.byKey(const Key('card_create_lease_p1')));
    await t.pumpAndSettle();
    expect(find.text('new lease'), findsOneWidget);
  });
}
```

Run: `flutter test test/unit/properties_filter_counts_test.dart test/widget/property_card_test.dart` — Expected: FAIL (symboles absents).

- [ ] **Step 3: Données — `currentRentCcCents`**

`property_list_item.dart` : ajouter au constructeur `this.currentRentCcCents,` et le champ documenté :

```dart
  /// Loyer charges comprises (loyer + charges) du bail actif, en centimes,
  /// ou `null` si vacant. Chiffre clé des cartes de liste.
  final int? currentRentCcCents;
```

Dans `PropertyListItem.fromJson`, après `rentHcCents = rentCents;` : `rentCcCents = total;` (déclarer `int? rentCcCents;` à côté de `rentHcCents`) et passer `currentRentCcCents: rentCcCents,`.

`property_repository.dart` (bloc `return PropertyListItem(` du listing Firestore) : ajouter `currentRentCcCents: rentHcCents == null ? null : rent + charges,`.

- [ ] **Step 4: Prédicat + compteurs**

`properties_filter_provider.dart` — remplacer le `switch` interne de `filteredPropertiesProvider` par l'appel au prédicat et ajouter :

```dart
/// Vrai si [item] correspond à [filter]. Source unique du filtrage (liste
/// filtrée ET compteurs des puces).
bool propertyMatchesFilter(PropertyListItem item, PropertyFilter filter) =>
    switch (filter) {
      PropertyFilter.all => true,
      PropertyFilter.occupied => item.activeLeaseId != null,
      PropertyFilter.vacant => item.activeLeaseId == null,
    };

/// Nombre d'éléments par filtre (compteurs des puces).
Map<PropertyFilter, int> propertyFilterCounts(List<PropertyListItem> items) => {
  for (final f in PropertyFilter.values)
    f: items.where((i) => propertyMatchesFilter(i, f)).length,
};

/// Compteurs des puces — `null` tant que la liste n'est pas chargée.
final propertyFilterCountsProvider = Provider<Map<PropertyFilter, int>?>((ref) {
  final items = ref.watch(propertiesListItemsProvider).valueOrNull;
  return items == null ? null : propertyFilterCounts(items);
});
```

et dans `filteredPropertiesProvider` : `return items.where((item) => propertyMatchesFilter(item, filter)).toList();`

- [ ] **Step 5: Carte adaptateur**

Réécrire `property_card.dart` (supprimer `_PropertyCardRow` et `_PropertyCardFooter` ; garder `_iconForType` seulement s'il reste utilisé, sinon le supprimer) :

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/summary_card.dart';
import '../../../../core/ui/theme/property_color.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/property_list_item.dart';
import 'property_status_mapper.dart';
import 'property_type_l10n.dart';

/// Carte d'un bien dans la liste — adaptateur [SummaryCard] (spec
/// 2026-09-29). Loué : loyer CC en chiffre clé ; vacant : action rapide
/// « Créer un bail ». Menu ⋮ : Voir le bail (si loué) · Modifier.
class PropertyCard extends StatelessWidget {
  const PropertyCard({super.key, required this.item, required this.onTap});

  final PropertyListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final property = item.property;
    final propertyId = property.id;
    final activeLeaseId = item.activeLeaseId;
    final pillData = propertyOccupancyPill(item, context);
    final colorKey = PropertyColorKey.resolve(
      entityId: propertyId,
      stored: property.colorKey,
    );
    final surfaceSuffix = property.surfaceM2 != null
        ? ' · ${l10n.propertiesSurfaceValue(property.surfaceM2!.toStringAsFixed(property.surfaceM2! % 1 == 0 ? 0 : 2))}'
        : '';
    final rentCc = item.currentRentCcCents;

    return SummaryCard(
      onTap: onTap,
      accentColor: colorKey.resolveColor(context),
      semanticLabel: l10n.propertiesCardSemanticLabel(
        property.name,
        pillData.label,
      ),
      title: property.name,
      subtitle: item.currentTenantName ?? l10n.propertiesNoTenant,
      keyFigure: rentCc == null
          ? null
          : SummaryKeyFigure(
              value: MoneyFormat.formatEurosFromCents(rentCc),
              caption: l10n.commonRentCcPerMonthCaption,
            ),
      status: StatusPill(
        tone: pillData.tone,
        label: pillData.label,
        icon: pillData.icon,
        size: StatusPillSize.sm,
      ),
      meta: '${property.address} · ${property.type.label(context)}$surfaceSuffix',
      quickAction: activeLeaseId == null
          ? SummaryQuickActionButton(
              key: Key('card_create_lease_$propertyId'),
              icon: Icons.add,
              label: l10n.propertiesCreateLease,
              onPressed: () =>
                  context.push('/leases/new?propertyId=$propertyId'),
            )
          : null,
      menuKey: Key('property_menu_$propertyId'),
      menuItems: [
        if (activeLeaseId != null)
          SummaryMenuItem(
            key: Key('card_view_lease_$propertyId'),
            label: l10n.propertiesViewLease,
            onSelected: () => context.push('/leases/$activeLeaseId'),
          ),
        SummaryMenuItem(
          key: Key('card_edit_property_$propertyId'),
          label: l10n.commonEdit,
          onSelected: () => context.push('/properties/$propertyId/edit'),
        ),
      ],
    );
  }
}
```

Vérifier que `propertyOccupancyPill` et `PropertyTypeL10n.label` sont bien les noms importés par l'ancien fichier (même imports).

- [ ] **Step 6: Barre de filtre en puces**

Réécrire le `build` de `PropertiesFilterBar` (supprimer les widgets privés dropdown/segments) :

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(propertyFilterProvider);
    final counts = ref.watch(propertyFilterCountsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: FilterChipsBar<PropertyFilter>(
        options: [
          for (final f in PropertyFilter.values)
            FilterChipOption(value: f, label: f.label(context), count: counts?[f]),
        ],
        selected: current,
        onSelected: (f) => ref.read(propertyFilterProvider.notifier).state = f,
        trailing: context.isMobile
            ? null
            : const ViewModeToggle(pageKey: 'properties'),
      ),
    );
  }
```

(Reprendre la `pageKey` exacte utilisée aujourd'hui par le `ViewModeToggle` de ce fichier, et l'extension de libellé existante `PropertyFilterL10n.label`.)

`properties_card_view.dart` : `mainAxisExtent: 220` → `mainAxisExtent: 124` (2 occurrences).

- [ ] **Step 7: Mettre à jour les tests existants**

- `test/widget/properties_filter_bar_test.dart` : remplacer les interactions dropdown / `SegmentedButton` par des taps sur `find.byKey(Key('filter_chip_${PropertyFilter.vacant}'))` ; conserver chaque assertion d'état (`propertyFilterProvider`).
- `test/widget/properties_card_view_test.dart` : les actions de pied passent par le menu (`find.byIcon(Icons.more_vert)` puis la clé de l'item) sauf « Créer un bail » (action rapide, même clé) ; conserver les destinations attendues.

Run: `flutter test test/unit/properties_filter_counts_test.dart test/widget/property_card_test.dart test/widget/properties_filter_bar_test.dart test/widget/properties_card_view_test.dart test/widget/properties_list_page_test.dart`
Expected: PASS. Puis `flutter test` complet : aucune régression.

- [ ] **Step 8: Commit**

```bash
dart format lib/features/properties test/widget/property_card_test.dart test/unit/properties_filter_counts_test.dart test/widget/properties_filter_bar_test.dart test/widget/properties_card_view_test.dart
flutter analyze
git add lib/features/properties/domain/property_list_item.dart lib/features/properties/data/property_repository.dart lib/features/properties/application/properties_filter_provider.dart lib/features/properties/presentation/widgets/property_card.dart lib/features/properties/presentation/widgets/properties_filter_bar.dart lib/features/properties/presentation/widgets/properties_card_view.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/unit/properties_filter_counts_test.dart test/widget/property_card_test.dart test/widget/properties_filter_bar_test.dart test/widget/properties_card_view_test.dart
git commit -m "feat(properties): carte « chiffre clé » + puces de filtre"
```

---

### Task 4: Baux — carte + puces

**Files:**
- Modify: `lib/features/leases/application/leases_filter_provider.dart`
- Modify: `lib/features/leases/presentation/widgets/lease_card.dart` (réécriture)
- Modify: `lib/features/leases/presentation/widgets/leases_filter_bar.dart`
- Modify: `lib/features/leases/presentation/widgets/leases_card_view.dart` (`220` → `124`, 2 occurrences)
- Test: `test/widget/lease_card_test.dart` (créé), `test/unit/leases_filter_counts_test.dart` (créé) ; mettre à jour `test/widget/leases_card_view_test.dart`, `test/widget/leases_filter_bar_test.dart`, `test/widget/leases_list_page_test.dart`

**Interfaces:**
- Consumes: Task 1, Task 2, clé `commonRentCcPerMonthCaption` (Task 3).
- Produces: `bool leaseMatchesFilter(LeaseListItem item, LeaseFilter filter, DateTime now)`, `Map<LeaseFilter, int> leaseFilterCounts(List<LeaseListItem> items, DateTime now)`, `final leaseFilterCountsProvider = Provider<Map<LeaseFilter, int>?>`.

Correspondance : titre `item.displayPropertyName(context)`, sous-titre `item.displayTenantName(context)`, chiffre clé `MoneyFormat.formatEurosFromCents(lease.totalAmountCents)` + `commonRentCcPerMonthCaption`, statut `leaseStatusPill(context, lease, isLate: item.isLate)`, meta = période (méthode `_formatPeriod` actuelle, conservée), action rapide `+ leasesCardPaymentButton` → `/leases/$leaseId/payments/new` (clé `card_add_payment_$leaseId`), menu : `leasesCardReceiptsButton` → `/leases/$leaseId/receipts` (clé `card_receipts_$leaseId`) ; si `lease.canRegularizeCharges` : `leasesRegularizeChargesMenuItem` → `/leases/$leaseId?action=regularize` (clé `menu_item_regularize_charges`) ; `commonEdit` → `/leases/$leaseId/edit` (clé `card_edit_lease_$leaseId`). `menuKey: Key('lease_menu_$leaseId')`. Liseré : `PropertyColorKey.resolve(entityId: lease.propertyId, stored: item.propertyColorKey).resolveColor(context)`. `semanticLabel` inchangé (`leasesCardSemanticLabel`).

- [ ] **Step 1: Tests qui échouent**

`test/unit/leases_filter_counts_test.dart` : construire 4 `LeaseListItem` (actif à jour, actif en retard `isLate: true`, actif renouvelable — `endDate` dans 2 mois —, terminé) en reprenant les fabriques de `test/widget/leases_filter_bar_test.dart` ou `leases_list_page_test.dart`, puis :

```dart
  test('leaseFilterCounts : priorité late > renewable > active', () {
    final now = DateTime(2026, 9, 29);
    final counts = leaseFilterCounts([actif, retard, renouvelable, termine], now);
    expect(counts, {
      LeaseFilter.all: 4,
      LeaseFilter.active: 1,
      LeaseFilter.renewable: 1,
      LeaseFilter.late: 1,
      LeaseFilter.terminated: 1,
    });
  });
```

(Choisir la date de fin du bail « renouvelable » d'après la règle de `isLeaseRenewable` — lire sa définition.)

`test/widget/lease_card_test.dart` (même squelette `MaterialApp.router` que la Task 3 avec routes `/leases/:id/payments/new`, `/leases/:id/receipts`, `/leases/:id/edit`, `/leases/:id`) :
- chiffre clé `800,00 €` + `CC / mois` affichés ;
- tap `card_add_payment_L1` → page paiement ;
- menu → `card_receipts_L1` → page quittances ;
- bail `canRegularizeCharges == false` → `menu_item_regularize_charges` absent du menu.

Run les 2 fichiers — Expected: FAIL.

- [ ] **Step 2: Prédicat + compteurs**

Dans `leases_filter_provider.dart`, extraire le `switch` actuel **sans le modifier** :

```dart
/// Vrai si [item] correspond à [filter]. Priorité (FEAT-028) : late >
/// renewable > active — un bail n'apparaît que dans un seul onglet.
bool leaseMatchesFilter(LeaseListItem item, LeaseFilter filter, DateTime now) {
  final lease = item.lease;
  return switch (filter) {
    LeaseFilter.all => true,
    LeaseFilter.active =>
      lease.status == LeaseStatus.active &&
          !item.isLate &&
          !isLeaseRenewable(lease, now),
    LeaseFilter.renewable =>
      lease.status == LeaseStatus.active &&
          !item.isLate &&
          isLeaseRenewable(lease, now),
    LeaseFilter.late => lease.status == LeaseStatus.active && item.isLate,
    LeaseFilter.terminated => lease.status == LeaseStatus.terminated,
  };
}

Map<LeaseFilter, int> leaseFilterCounts(List<LeaseListItem> items, DateTime now) => {
  for (final f in LeaseFilter.values)
    f: items.where((i) => leaseMatchesFilter(i, f, now)).length,
};

/// Compteurs des puces — `null` tant que la liste n'est pas chargée.
final leaseFilterCountsProvider = Provider<Map<LeaseFilter, int>?>((ref) {
  final items = ref.watch(leasesListProvider).valueOrNull;
  return items == null ? null : leaseFilterCounts(items, DateTime.now());
});
```

et `filteredLeasesProvider` : `final now = DateTime.now(); return leases.where((item) => leaseMatchesFilter(item, filter, now)).toList();`

- [ ] **Step 3: Carte adaptateur**

Réécrire `lease_card.dart` : garder `_formatPeriod` (déplacée en méthode privée de `LeaseCard`), supprimer `_LeaseCardRow`, `_LeaseCardFooter`, `_LeaseCardMenuAction`, `_RegularizeChargesMenu`. Le `build` retourne :

```dart
    return SummaryCard(
      onTap: onTap,
      accentColor: colorKey.resolveColor(context),
      semanticLabel: l10n.leasesCardSemanticLabel(
        item.displayPropertyName(context),
        item.displayTenantName(context),
      ),
      title: item.displayPropertyName(context),
      subtitle: item.displayTenantName(context),
      keyFigure: SummaryKeyFigure(
        value: MoneyFormat.formatEurosFromCents(lease.totalAmountCents),
        caption: l10n.commonRentCcPerMonthCaption,
      ),
      status: StatusPill(
        tone: pillData.tone,
        label: pillData.label,
        icon: pillData.icon,
        size: StatusPillSize.sm,
      ),
      meta: _formatPeriod(context, lease.startDate, lease.endDate),
      quickAction: SummaryQuickActionButton(
        key: Key('card_add_payment_${lease.id}'),
        icon: Icons.add,
        label: l10n.leasesCardPaymentButton,
        onPressed: () => context.push('/leases/${lease.id}/payments/new'),
      ),
      menuKey: Key('lease_menu_${lease.id}'),
      menuItems: [
        SummaryMenuItem(
          key: Key('card_receipts_${lease.id}'),
          label: l10n.leasesCardReceiptsButton,
          onSelected: () => context.push('/leases/${lease.id}/receipts'),
        ),
        // Gate légal inchangé (FEAT-030/042) : mode provisions uniquement.
        if (lease.canRegularizeCharges)
          SummaryMenuItem(
            key: const Key('menu_item_regularize_charges'),
            label: l10n.leasesRegularizeChargesMenuItem,
            onSelected: () =>
                context.push('/leases/${lease.id}?action=regularize'),
          ),
        SummaryMenuItem(
          key: Key('card_edit_lease_${lease.id}'),
          label: l10n.commonEdit,
          onSelected: () => context.push('/leases/${lease.id}/edit'),
        ),
      ],
    );
```

Vérifier dans `lib/core/router/app_router.dart` que `/leases/:id/edit` existe (sous-route `edit` du bloc `/leases`) ; sinon retirer l'item « Modifier ».

- [ ] **Step 4: Barre de filtre**

Même patron que Task 3 Step 6 avec `LeaseFilter`, `leaseFilterProvider`, `leaseFilterCountsProvider`, `ViewModeToggle(pageKey: 'leases')`, extension `LeaseFilterL10n.label`. `leases_card_view.dart` : `220` → `124`.

- [ ] **Step 5: Tests existants**

`leases_filter_bar_test.dart`, `leases_card_view_test.dart`, `leases_list_page_test.dart`, `leases_table_view_test.dart` : remplacer dropdown/segments par les puces, les boutons de pied par l'action rapide (`card_add_payment_…`) ou le menu (`lease_menu_…` puis `card_receipts_…`). Mêmes destinations attendues.

Run: `flutter test test/unit/leases_filter_counts_test.dart test/widget/lease_card_test.dart test/widget/leases_filter_bar_test.dart test/widget/leases_card_view_test.dart test/widget/leases_list_page_test.dart test/widget/leases_table_view_test.dart` puis `flutter test`.
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
dart format lib/features/leases test/widget/lease_card_test.dart test/unit/leases_filter_counts_test.dart test/widget/leases_filter_bar_test.dart test/widget/leases_card_view_test.dart test/widget/leases_list_page_test.dart test/widget/leases_table_view_test.dart
flutter analyze
git add lib/features/leases/application/leases_filter_provider.dart lib/features/leases/presentation/widgets/lease_card.dart lib/features/leases/presentation/widgets/leases_filter_bar.dart lib/features/leases/presentation/widgets/leases_card_view.dart test/unit/leases_filter_counts_test.dart test/widget/lease_card_test.dart test/widget/leases_filter_bar_test.dart test/widget/leases_card_view_test.dart test/widget/leases_list_page_test.dart test/widget/leases_table_view_test.dart
git commit -m "feat(leases): carte « chiffre clé » + puces de filtre"
```

---

### Task 5: Locataires — carte + puces (Appeler / email)

**Files:**
- Modify: `lib/features/tenants/domain/tenant_list_item.dart` (champ `activeLeaseChargesCents`)
- Modify: `lib/features/tenants/data/tenant_repository.dart:285-296` (renseigner le champ)
- Modify: `lib/features/tenants/application/tenants_filter_provider.dart`
- Modify: `lib/features/tenants/presentation/widgets/tenant_card.dart` (réécriture)
- Modify: `lib/features/tenants/presentation/widgets/tenants_filter_bar.dart`
- Modify: `lib/features/tenants/presentation/widgets/tenants_card_view.dart` (`220` → `124`, 2 occurrences)
- Modify: `android/app/src/main/AndroidManifest.xml` (`<queries>`)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: `test/widget/tenant_card_test.dart` (créé), `test/unit/tenants_filter_counts_test.dart` (créé) ; mettre à jour `test/widget/tenants_card_view_test.dart`, `test/widget/tenants_filter_bar_test.dart`, `test/unit/tenant_repository_firestore_test.dart` (nouveau champ)

**Interfaces:**
- Consumes: Task 1, Task 2, `commonRentCcPerMonthCaption`.
- Produces: `TenantListItem.activeLeaseChargesCents` (`int?`), `bool tenantMatchesFilter(TenantListItem, TenantFilter)`, `Map<TenantFilter, int> tenantFilterCounts(List<TenantListItem>)`, `final tenantFilterCountsProvider = Provider<Map<TenantFilter, int>?>`, l10n `tenantsCallButton`, `tenantsEmailButton`.

Correspondance :
- Avec bail : sous-titre `item.currentPropertyName`, chiffre clé `formatEurosFromCents(activeLeaseRentCents + (activeLeaseChargesCents ?? 0))` + `commonRentCcPerMonthCaption`, meta `item.activeLeasePeriodLabel`, action rapide : si `tenant.phone` non vide → `✆ tenantsCallButton` (icône `Icons.call_outlined`, `launchUrl(Uri(scheme: 'tel', path: phone))`, clé `card_call_$tenantId`) ; sinon `✉ tenantsEmailButton` (icône `Icons.mail_outline`, `launchUrl(Uri(scheme: 'mailto', path: email))`, clé `card_email_$tenantId`). Menu : `tenantsViewLeaseButton` → `/leases/$activeLeaseId` (clé `card_view_lease_$tenantId`) ; `tenantsEmailButton` (seulement si l'email n'est pas déjà l'action rapide, clé `menu_email_$tenantId`) ; `commonEdit` → `/tenants/$tenantId/edit` (clé `card_edit_tenant_$tenantId`).
- Sans bail : sous-titre `tenant.email`, pas de chiffre clé, action rapide `+ tenantsCreateLeaseButton` → `/leases/new?tenantId=$tenantId` (clé `card_create_lease_$tenantId`). Menu : `tenantsEmailButton` (clé `menu_email_$tenantId`) · `commonEdit`.
- Statut `tenantOccupancyPill(context, item)`. Liseré : couleur du bien occupé si `currentPropertyId != null`, sinon `null` (gris).

- [ ] **Step 1: l10n + manifeste**

`app_en.arb` : `"tenantsCallButton": "Call",` (`@` : « Quick action: phone the tenant ») ; `"tenantsEmailButton": "Send an email",` (`@` : « Quick action / menu: email the tenant »).
`app_fr.arb` : `"tenantsCallButton": "Appeler",` ; `"tenantsEmailButton": "Envoyer un email",`.
Run `flutter gen-l10n`.

`AndroidManifest.xml`, dans `<queries>`, à côté de l'intent `SENDTO`/`mailto` :

```xml
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
```

- [ ] **Step 2: Tests qui échouent**

`test/unit/tenants_filter_counts_test.dart` : 3 items (2 avec `activeLeaseId`, 1 sans) → `{all: 3, withActiveLease: 2, withoutActiveLease: 1}` ; + `tenantMatchesFilter` sur chaque cas.

`test/widget/tenant_card_test.dart` (squelette Task 3 ; routes `/leases/new`, `/leases/:id`, `/tenants/:id/edit`) :
- avec bail + téléphone : chiffre clé `850,00 €` pour `activeLeaseRentCents: 80000, activeLeaseChargesCents: 5000` ; `card_call_t1` présent ; `card_email_t1` absent ; le menu contient `menu_email_t1` ;
- avec bail sans téléphone : `card_email_t1` présent, `menu_email_t1` absent du menu ;
- sans bail : tap `card_create_lease_t1` → page `new lease`.
(Le lancement `tel:`/`mailto:` n'est pas exécuté en test : vérifier seulement la présence des boutons.)

Run — Expected: FAIL.

- [ ] **Step 3: Données**

`tenant_list_item.dart` : ajouter `this.activeLeaseChargesCents,` au constructeur et

```dart
  /// Charges mensuelles du bail actif en centimes, ou `null` si sans bail.
  /// Avec [activeLeaseRentCents] : chiffre clé « CC / mois » des cartes.
  final int? activeLeaseChargesCents;
```

Dans `fromJson` : `chargesCents = activeLease['charges_amount_cents'] as int?;` (déclarer `int? chargesCents;`) et `activeLeaseChargesCents: chargesCents,`.
`tenant_repository.dart` (bloc `return TenantListItem(` avec bail) : `activeLeaseChargesCents: lease['chargesAmountCents'] as int?,`. Vérifier que la projection des baux actifs lue par ce repository contient bien `chargesAmountCents` (même collection `leases` que le repository des biens) ; ajuster `test/unit/tenant_repository_firestore_test.dart` si ses fixtures l'omettent.

- [ ] **Step 4: Prédicat + compteurs**

```dart
bool tenantMatchesFilter(TenantListItem item, TenantFilter filter) =>
    switch (filter) {
      TenantFilter.all => true,
      TenantFilter.withActiveLease => item.activeLeaseId != null,
      TenantFilter.withoutActiveLease => item.activeLeaseId == null,
    };

Map<TenantFilter, int> tenantFilterCounts(List<TenantListItem> items) => {
  for (final f in TenantFilter.values)
    f: items.where((i) => tenantMatchesFilter(i, f)).length,
};

final tenantFilterCountsProvider = Provider<Map<TenantFilter, int>?>((ref) {
  final items = ref.watch(tenantsListItemsProvider).valueOrNull;
  return items == null ? null : tenantFilterCounts(items);
});
```

`filteredTenantsProvider` utilise `tenantMatchesFilter`.

- [ ] **Step 5: Carte adaptateur**

Réécrire `tenant_card.dart` (supprimer `_TenantCardRow`, `_TenantCardFooter`) :

```dart
    final phone = tenant.phone?.trim();
    final hasPhone = phone != null && phone.isNotEmpty;
    final hasLease = activeLeaseId != null;
    final rent = item.activeLeaseRentCents;
    final emailInQuickAction = hasLease && !hasPhone;

    Widget emailButton() => SummaryQuickActionButton(
      key: Key('card_email_$tenantId'),
      icon: Icons.mail_outline,
      label: l10n.tenantsEmailButton,
      onPressed: () => launchUrl(Uri(scheme: 'mailto', path: tenant.email)),
    );

    return SummaryCard(
      onTap: onTap,
      accentColor: colorKey?.resolveColor(context),
      semanticLabel: '${tenant.firstName} ${tenant.lastName} — ${pillData.label}',
      title: '${tenant.firstName} ${tenant.lastName}',
      subtitle: hasLease ? item.currentPropertyName : tenant.email,
      keyFigure: hasLease && rent != null
          ? SummaryKeyFigure(
              value: MoneyFormat.formatEurosFromCents(
                rent + (item.activeLeaseChargesCents ?? 0),
              ),
              caption: l10n.commonRentCcPerMonthCaption,
            )
          : null,
      status: StatusPill(
        tone: pillData.tone,
        label: pillData.label,
        icon: pillData.icon,
        size: StatusPillSize.sm,
      ),
      meta: hasLease ? item.activeLeasePeriodLabel : null,
      quickAction: !hasLease
          ? SummaryQuickActionButton(
              key: Key('card_create_lease_$tenantId'),
              icon: Icons.add,
              label: l10n.tenantsCreateLeaseButton,
              onPressed: () => context.push('/leases/new?tenantId=$tenantId'),
            )
          : hasPhone
          ? SummaryQuickActionButton(
              key: Key('card_call_$tenantId'),
              icon: Icons.call_outlined,
              label: l10n.tenantsCallButton,
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            )
          : emailButton(),
      menuKey: Key('tenant_menu_$tenantId'),
      menuItems: [
        if (hasLease)
          SummaryMenuItem(
            key: Key('card_view_lease_$tenantId'),
            label: l10n.tenantsViewLeaseButton,
            onSelected: () => context.push('/leases/$activeLeaseId'),
          ),
        if (!emailInQuickAction)
          SummaryMenuItem(
            key: Key('menu_email_$tenantId'),
            label: l10n.tenantsEmailButton,
            onSelected: () =>
                launchUrl(Uri(scheme: 'mailto', path: tenant.email)),
          ),
        SummaryMenuItem(
          key: Key('card_edit_tenant_$tenantId'),
          label: l10n.commonEdit,
          onSelected: () => context.push('/tenants/$tenantId/edit'),
        ),
      ],
    );
```

Imports à ajouter : `package:url_launcher/url_launcher.dart`, `summary_card.dart`, `money_format.dart`. `colorKey` calculé comme aujourd'hui (`null` sans bien).

- [ ] **Step 6: Barre de filtre + vue cartes**

Patron Task 3 Step 6 avec `TenantFilter`, `tenantFilterProvider`, `tenantFilterCountsProvider`, `ViewModeToggle(pageKey: 'tenants')`, `TenantFilterL10n.label`. `tenants_card_view.dart` : `220` → `124`.

- [ ] **Step 7: Tests existants + suite**

Mettre à jour `tenants_filter_bar_test.dart`, `tenants_card_view_test.dart` (actions via menu / action rapide, mêmes destinations).
Run: `flutter test test/unit/tenants_filter_counts_test.dart test/widget/tenant_card_test.dart test/widget/tenants_filter_bar_test.dart test/widget/tenants_card_view_test.dart test/unit/tenant_repository_firestore_test.dart` puis `flutter test`.
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
dart format lib/features/tenants test/widget/tenant_card_test.dart test/unit/tenants_filter_counts_test.dart test/widget/tenants_filter_bar_test.dart test/widget/tenants_card_view_test.dart test/unit/tenant_repository_firestore_test.dart
flutter analyze
git add lib/features/tenants/domain/tenant_list_item.dart lib/features/tenants/data/tenant_repository.dart lib/features/tenants/application/tenants_filter_provider.dart lib/features/tenants/presentation/widgets/tenant_card.dart lib/features/tenants/presentation/widgets/tenants_filter_bar.dart lib/features/tenants/presentation/widgets/tenants_card_view.dart android/app/src/main/AndroidManifest.xml lib/l10n/app_en.arb lib/l10n/app_fr.arb test/unit/tenants_filter_counts_test.dart test/widget/tenant_card_test.dart test/widget/tenants_filter_bar_test.dart test/widget/tenants_card_view_test.dart test/unit/tenant_repository_firestore_test.dart
git commit -m "feat(tenants): carte « chiffre clé » (Appeler / email) + puces de filtre"
```

---

### Task 6: Quittances — carte, timeline mobile, puces

**Files:**
- Modify: `lib/features/receipts/presentation/widgets/receipt_card.dart` (réécriture du `build`)
- Modify: `lib/features/receipts/presentation/widgets/receipts_timeline_view.dart` (éléments = `ReceiptCard`, colonne de marqueurs supprimée)
- Modify: `lib/features/receipts/application/receipts_filter_provider.dart`
- Modify: `lib/features/receipts/presentation/widgets/receipts_filter_bar.dart`
- Modify: `lib/features/receipts/presentation/widgets/receipts_card_view.dart` (`244` → `132`, 2 occurrences)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: `test/widget/receipt_card_test.dart` (créé), `test/unit/receipts_status_counts_test.dart` (créé) ; mettre à jour `test/widget/receipts_card_view_test.dart`, `test/widget/receipts_timeline_view_test.dart`, `test/widget/receipts_filter_bar_test.dart`

**Interfaces:**
- Consumes: Task 1, Task 2.
- Produces: `bool receiptMatchesStatus(Receipt r, ReceiptStatusFilter f)`, `Map<ReceiptStatusFilter, int> receiptStatusCounts(List<Receipt> receipts, int? year)`, `final receiptStatusCountsProvider = Provider.family.autoDispose<Map<ReceiptStatusFilter, int>?, String>` (par `leaseId`, compte dans l'année sélectionnée), l10n `receiptsCardTotalCaption`.

Correspondance : titre `receiptPeriodMonthYear(receipt)`, sous-titre `receiptSecondaryLine(context, receipt)`, chiffre clé `receipt.totalEuros` formaté comme aujourd'hui (valeur passée à `receiptsCardAmountCc`, sans le suffixe « CC ») + légende `receiptsCardTotalCaption` (« loyer + charges » / « rent + charges »), statut `receiptStatusPill(context, receipt)`, meta : si `isStale && !isVoided` → `l10n.receiptsCardStaleWarning` ; si `isVoided && voidedReason != null` → `voidedReason` ; sinon `null`. Action rapide : **le widget `ShareReceiptButton` existant** (mêmes paramètres qu'aujourd'hui ; il gère déjà ses états désactivés/tooltips). Menu : `receiptsOpenPdfLabel` → `_openPdf` (clé `btn_pdf_card_${receipt.id}`) ; si `!receipt.isVoided` : `receiptsVoidMenuItem` destructive → `_showVoidDialog` (clé `btn_void_card_${receipt.id}`), désactivé pendant `VoidReceiptSubmitting` (ne pas l'afficher dans ce cas). Tap carte → `_openPdf` (inchangé). Liseré : `propertyColorKey?.resolveColor(context)`. `key: Key('receipt_card_${receipt.id}')` et `_listenVoidState` conservés.

- [ ] **Step 1: l10n**

`app_en.arb` : `"receiptsCardTotalCaption": "rent + charges",` (`@` : « Caption under the receipt total key figure ») ; `app_fr.arb` : `"receiptsCardTotalCaption": "loyer + charges",`. `flutter gen-l10n`.

Si `ShareReceiptButton` n'est pas assez compact pour l'emplacement d'action rapide (hauteur > 40 px), lui ajouter un paramètre optionnel `bool compact = false` qui applique le style de `SummaryQuickActionButton` — sans changer son comportement.

- [ ] **Step 2: Tests qui échouent**

`test/unit/receipts_status_counts_test.dart` : fabriquer 4 `Receipt` (partagée, payée non partagée, annulée, année précédente) à partir de `_makeReceipt` de `test/widget/lease_context_banner_test.dart` ; vérifier `receiptMatchesStatus` pour chaque filtre (mêmes règles que le `switch` actuel) et `receiptStatusCounts(receipts, 2026)` qui ignore l'année précédente, `receiptStatusCounts(receipts, null)` qui compte tout.

`test/widget/receipt_card_test.dart` (squelette avec `ProviderScope`, overrides des repositories comme dans `test/widget/receipts_card_view_test.dart`) :
- chiffre clé + « loyer + charges » affichés ;
- quittance annulée : menu sans `btn_void_card_…` ;
- quittance périmée : meta « Quittance périmée » visible ;
- `ShareReceiptButton` présent.

Run — Expected: FAIL.

- [ ] **Step 3: Prédicat + compteurs**

```dart
/// Vrai si [r] correspond au filtre de statut (règles inchangées).
bool receiptMatchesStatus(Receipt r, ReceiptStatusFilter f) => switch (f) {
  ReceiptStatusFilter.all => true,
  ReceiptStatusFilter.sent => r.hasBeenShared && !r.isVoided,
  ReceiptStatusFilter.paid => r.paymentIds.isNotEmpty && !r.isVoided,
  ReceiptStatusFilter.voided => r.isVoided,
};

/// Compteurs par statut, restreints à [year] quand il est défini.
Map<ReceiptStatusFilter, int> receiptStatusCounts(List<Receipt> receipts, int? year) {
  final inYear = year == null
      ? receipts
      : receipts.where((r) => r.periodStart.year == year).toList();
  return {
    for (final f in ReceiptStatusFilter.values)
      f: inYear.where((r) => receiptMatchesStatus(r, f)).length,
  };
}

final receiptStatusCountsProvider = Provider.family
    .autoDispose<Map<ReceiptStatusFilter, int>?, String>((ref, leaseId) {
      final receipts = ref.watch(leaseReceiptsProvider(leaseId)).valueOrNull;
      final year = ref.watch(receiptYearFilterProvider(leaseId));
      return receipts == null ? null : receiptStatusCounts(receipts, year);
    });
```

`filteredReceiptsProvider` : remplacer le `switch` interne par `receiptMatchesStatus(r, filter)`.

- [ ] **Step 4: Carte adaptateur**

Dans `receipt_card.dart`, remplacer le `return EntityCard(...)` par un `SummaryCard` selon la correspondance ci-dessus ; supprimer `_ReceiptCardBody`, `_ReceiptCardRow`, `_ReceiptCardFooter` ; garder `_listenVoidState`, `_openPdf`, `_showVoidDialog`. Lire `ref.watch(voidReceiptControllerProvider(receipt.id)) is VoidReceiptSubmitting` dans `build` pour masquer l'item Annuler pendant l'annulation.

- [ ] **Step 5: Timeline mobile**

Dans `receipts_timeline_view.dart`, `_ReceiptTimelineItem.build` retourne :

```dart
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ReceiptCard(
        receipt: receipt,
        leaseId: leaseId,
        tenantEmail: tenantEmail,
        tenantFirstName: tenantFirstName,
        propertyAddress: propertyAddress,
        landlordFullName: landlordFullName,
        propertyColorKey: propertyColorKey,
      ),
    );
```

Ajouter `propertyColorKey` (`PropertyColorKey?`) aux paramètres de `ReceiptsTimelineView` / `_ReceiptTimelineItem` et le passer depuis `lease_receipts_page.dart` exactement comme pour `ReceiptsCardView`. Supprimer `_TimelineMarker`, `_TimelineItemContent` et le paramètre `isLast` devenus inutiles. Les en-têtes d'année (`_YearHeader`) et le squelette de chargement restent.

- [ ] **Step 6: Barre de filtre**

`ReceiptsFilterBar.build` : `FilterChipsBar<ReceiptStatusFilter>` (options `ReceiptStatusFilter.values`, libellés `ReceiptStatusFilterL10n.label`, compteurs `receiptStatusCountsProvider(leaseId)`), `trailing` = `Row(mainAxisSize: min)` avec le sélecteur d'année existant (réutiliser le widget/dropdown d'année actuel du fichier, sur toutes les largeurs, s'il y a au moins une année) puis `ViewModeToggle(pageKey: _viewModeKey)` si `!context.isMobile`. Supprimer les widgets privés mobile/desktop devenus inutiles.

`receipts_card_view.dart` : `244` → `132` (2 occurrences).

- [ ] **Step 7: Tests existants + suite**

Mettre à jour `receipts_card_view_test.dart` (boutons PDF/Annuler via le menu, mêmes clés), `receipts_timeline_view_test.dart` (plus de marqueurs ; vérifier les en-têtes d'année et une `ReceiptCard` par quittance), `receipts_filter_bar_test.dart` (puces).
Run: `flutter test test/unit/receipts_status_counts_test.dart test/widget/receipt_card_test.dart test/widget/receipts_card_view_test.dart test/widget/receipts_timeline_view_test.dart test/widget/receipts_filter_bar_test.dart` puis `flutter test`.
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
dart format lib/features/receipts test/widget/receipt_card_test.dart test/unit/receipts_status_counts_test.dart test/widget/receipts_card_view_test.dart test/widget/receipts_timeline_view_test.dart test/widget/receipts_filter_bar_test.dart
flutter analyze
git add lib/features/receipts/presentation/widgets/receipt_card.dart lib/features/receipts/presentation/widgets/receipts_timeline_view.dart lib/features/receipts/presentation/lease_receipts_page.dart lib/features/receipts/application/receipts_filter_provider.dart lib/features/receipts/presentation/widgets/receipts_filter_bar.dart lib/features/receipts/presentation/widgets/receipts_card_view.dart lib/features/receipts/presentation/widgets/share_receipt_button.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/unit/receipts_status_counts_test.dart test/widget/receipt_card_test.dart test/widget/receipts_card_view_test.dart test/widget/receipts_timeline_view_test.dart test/widget/receipts_filter_bar_test.dart
git commit -m "feat(receipts): carte « chiffre clé », timeline compacte, puces de filtre"
```

(Retirer `share_receipt_button.dart` de la liste s'il n'a pas été modifié.)

---

### Task 7: État projet + vérification finale

**Files:**
- Modify: `docs/state/FEATURES.md` (ligne FEAT-059)
- Modify: `docs/state/CHANGELOG.md` (entrée FEAT-059)

- [ ] **Step 1: FEATURES.md**

Ajouter après FEAT-058 :

```markdown
| FEAT-059 | Cartes de liste « chiffre clé » + puces de filtre (biens, baux, locataires, quittances) | ✅ done | properties, leases, tenants, receipts | feat/list-summary-cards, docs/superpowers/specs/2026-09-29-mobile-list-cards-design.md |
```

(Adapter aux colonnes exactes du tableau existant.)

- [ ] **Step 2: CHANGELOG.md**

Préfixer dans la période courante :

```markdown
### FEAT-059 — Cartes de liste « chiffre clé » + puces de filtre (2026-09-29)
- `SummaryCard` (core) : liseré couleur du bien, montant en gros à droite, 1 action rapide + menu ⋮ ; ~90 px au lieu de ~150. Adaptateurs : `PropertyCard`, `LeaseCard`, `TenantCard` (Appeler / email), `ReceiptCard` (Envoyer = `ShareReceiptButton`).
- `FilterChipsBar` (core) : puces avec compteurs dérivés client (`…FilterCountsProvider`, prédicats `…MatchesFilter` extraits sans changement de règle) ; remplace dropdown mobile et `SegmentedButton` desktop.
- Quittances mobile : timeline sans colonne de marqueurs, en-têtes d'année conservés.
- Données : `PropertyListItem.currentRentCcCents`, `TenantListItem.activeLeaseChargesCents`. Android : intent `DIAL` dans `<queries>`.
- Client uniquement — aucun déploiement backend.
```

- [ ] **Step 3: Vérification complète**

```bash
export PATH=/opt/homebrew/bin:$PATH
git ls-files -m -o --exclude-standard '*.dart' | xargs dart format --set-exit-if-changed -o none
flutter analyze
flutter test
```

Expected : format OK, `No issues found!`, `All tests passed!`.

- [ ] **Step 4: Commit**

```bash
git add docs/state/FEATURES.md docs/state/CHANGELOG.md
git commit -m "docs(state): FEAT-059 cartes de liste « chiffre clé »"
```
