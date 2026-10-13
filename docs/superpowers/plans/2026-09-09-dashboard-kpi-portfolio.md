# Dashboard — KPI patrimoniaux (occupation, patrimoine) + dé-dup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer les compteurs KPI redondants avec le panneau « À traiter / À venir » (loyers, retards, renouvellements) par deux KPI patrimoniaux — taux d'occupation et patrimoine (Σ prix d'achat) — en gardant « Documents en attente ».

**Architecture:** Un provider dérivé calcule occupation + patrimoine depuis `propertiesListItemsProvider` (déjà chargé par le dashboard, zéro nouvelle requête). `KpiGrid` devient un `ConsumerWidget` qui lit ce provider pour les deux nouvelles cartes et garde `snapshot.docs` pour la troisième.

**Tech Stack:** Flutter + Riverpod 2.6 (Provider / AsyncNotifierProvider), GoRouter, freezed (existant), i18n `.arb` + `flutter gen-l10n`.

## Global Constraints

- **Zéro nouvelle requête Firestore** : dériver `propertiesListItemsProvider` (type `AsyncNotifierProvider<PropertiesListItemsNotifier, List<PropertyListItem>>`). Aucun accès Firestore direct.
- **Occupé** = `PropertyListItem.activeLeaseId != null`. **Patrimoine** = somme des `item.property.purchasePriceCents` non nuls (montant à l'achat, factuel).
- **Jetons uniquement** : couleurs via `Theme.of(context).extension<AppColors>()!` (`.success` / `.warning` / `.neutral` — chacun un `StatusColorSet` avec `.solid`) ; espacement via `AppSpacing`. Aucune couleur en dur.
- **i18n** : tout libellé/sous-titre via `context.l10n.<clé>` ; clés ajoutées dans `lib/l10n/app_fr.arb` ET `lib/l10n/app_en.arb`, puis `flutter gen-l10n`. Les `.dart` générés sont gitignorés (ne pas les committer).
- **Réutilise** `KpiCard(icon, label, value, subtitle?, semanticColor?, onTap?)` — ne pas le modifier.
- **Cas dégradés** : 0 bien → occupation « — · Aucun bien » (pas de division par zéro) ; aucun prix renseigné → patrimoine « — · Renseignez le prix d'achat » (pas de « 0 € »).
- Montants formatés via `MoneyFormat.formatEurosFromCents(int)`.
- Chaque tâche finit par `dart format` + `flutter analyze` clean sur les fichiers touchés, et commit (chemins explicites, jamais `git add -A`).

---

### Task 1 : Provider dérivé `dashboardPortfolioKpisProvider`

**Files:**
- Create: `lib/features/dashboard/application/dashboard_portfolio_kpis_provider.dart`
- Test: `test/unit/dashboard_portfolio_kpis_provider_test.dart`

**Interfaces:**
- Consumes: `propertiesListItemsProvider` (`AsyncNotifierProvider<PropertiesListItemsNotifier, List<PropertyListItem>>`), `PropertyListItem` (`activeLeaseId` `String?`, `property` `Property` avec `purchasePriceCents` `int?`).
- Produces:
  - `class PortfolioKpis` avec champs `int occupied`, `int total`, `int patrimoineCents`, `int propertiesWithPrice`, et getters `bool get hasProperties` (`total > 0`), `int get vacant` (`total - occupied`), `int? get occupancyPercent` (`null` si `total==0`, sinon `((occupied/total)*100).round()`), `bool get hasAnyPrice` (`propertiesWithPrice > 0`).
  - `final dashboardPortfolioKpisProvider = Provider<AsyncValue<PortfolioKpis>>((ref) {...});`

- [ ] **Step 1 : Test qui échoue**

```dart
// test/unit/dashboard_portfolio_kpis_provider_test.dart
import 'package:easyrent/features/dashboard/application/dashboard_portfolio_kpis_provider.dart';
import 'package:easyrent/features/properties/application/properties_list_provider.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePropsNotifier extends PropertiesListItemsNotifier {
  _FakePropsNotifier(this._items);
  final List<PropertyListItem> _items;
  @override
  Future<List<PropertyListItem>> build() async => _items;
}

PropertyListItem _item({
  required String id,
  String? activeLeaseId,
  int? purchasePriceCents,
}) => PropertyListItem(
  property: Property(
    id: id,
    landlordId: 'lord1',
    label: 'Bien $id',
    addressStreet: '1 rue',
    addressPostalCode: '75001',
    addressCity: 'Paris',
    purchasePriceCents: purchasePriceCents,
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  ),
  activeLeaseId: activeLeaseId,
);

void main() {
  ProviderContainer containerWith(List<PropertyListItem> items) =>
      ProviderContainer(overrides: [
        propertiesListItemsProvider.overrideWith(() => _FakePropsNotifier(items)),
      ]);

  test('occupation + patrimoine (2 biens, 1 loué, prix des 2)', () async {
    final c = containerWith([
      _item(id: 'a', activeLeaseId: 'l1', purchasePriceCents: 11800000),
      _item(id: 'b', activeLeaseId: null, purchasePriceCents: 11800000),
    ]);
    addTearDown(c.dispose);
    await c.read(propertiesListItemsProvider.future);
    final k = c.read(dashboardPortfolioKpisProvider).value!;
    expect(k.occupied, 1);
    expect(k.total, 2);
    expect(k.vacant, 1);
    expect(k.occupancyPercent, 50);
    expect(k.patrimoineCents, 23600000);
    expect(k.propertiesWithPrice, 2);
    expect(k.hasProperties, isTrue);
    expect(k.hasAnyPrice, isTrue);
  });

  test('aucun bien → occupancyPercent null, hasProperties false', () async {
    final c = containerWith([]);
    addTearDown(c.dispose);
    await c.read(propertiesListItemsProvider.future);
    final k = c.read(dashboardPortfolioKpisProvider).value!;
    expect(k.total, 0);
    expect(k.occupancyPercent, isNull);
    expect(k.hasProperties, isFalse);
    expect(k.hasAnyPrice, isFalse);
  });

  test('prix partiellement renseignés', () async {
    final c = containerWith([
      _item(id: 'a', activeLeaseId: 'l1', purchasePriceCents: 11800000),
      _item(id: 'b', activeLeaseId: 'l2', purchasePriceCents: null),
    ]);
    addTearDown(c.dispose);
    await c.read(propertiesListItemsProvider.future);
    final k = c.read(dashboardPortfolioKpisProvider).value!;
    expect(k.patrimoineCents, 11800000);
    expect(k.propertiesWithPrice, 1);
    expect(k.occupancyPercent, 100);
  });
}
```

> NOTE : vérifier les champs `required` réels du constructeur freezed `Property` et du `PropertyListItem` et ajuster `_item`. `PropertyListItem` requiert `property` + `activeLeaseId?` + `currentTenantName?` + `currentRentLabel?` + `currentRentHcCents?`. Ajouter tout champ `required` que le compilateur signale sur `Property`.

- [ ] **Step 2 : Lancer → échoue**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/unit/dashboard_portfolio_kpis_provider_test.dart`
Expected: FAIL (provider/modèle introuvables).

- [ ] **Step 3 : Implémenter modèle + provider**

```dart
// lib/features/dashboard/application/dashboard_portfolio_kpis_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../properties/application/properties_list_provider.dart';

/// KPI patrimoniaux du dashboard, dérivés de la liste des biens
/// ([propertiesListItemsProvider]) — aucune requête propre.
class PortfolioKpis {
  const PortfolioKpis({
    required this.occupied,
    required this.total,
    required this.patrimoineCents,
    required this.propertiesWithPrice,
  });

  /// Nombre de biens avec un bail actif.
  final int occupied;

  /// Nombre total de biens.
  final int total;

  /// Somme des prix d'achat renseignés (centimes).
  final int patrimoineCents;

  /// Nombre de biens dont le prix d'achat est renseigné.
  final int propertiesWithPrice;

  bool get hasProperties => total > 0;
  int get vacant => total - occupied;

  /// `null` s'il n'y a aucun bien (pas de division par zéro).
  int? get occupancyPercent =>
      total == 0 ? null : ((occupied / total) * 100).round();

  bool get hasAnyPrice => propertiesWithPrice > 0;
}

final dashboardPortfolioKpisProvider = Provider<AsyncValue<PortfolioKpis>>((
  ref,
) {
  final asyncItems = ref.watch(propertiesListItemsProvider);
  return asyncItems.whenData((items) {
    final occupied = items.where((i) => i.activeLeaseId != null).length;
    var patrimoine = 0;
    var withPrice = 0;
    for (final i in items) {
      final price = i.property.purchasePriceCents;
      if (price != null) {
        patrimoine += price;
        withPrice++;
      }
    }
    return PortfolioKpis(
      occupied: occupied,
      total: items.length,
      patrimoineCents: patrimoine,
      propertiesWithPrice: withPrice,
    );
  });
});
```

- [ ] **Step 4 : Lancer → passe**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/unit/dashboard_portfolio_kpis_provider_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5 : analyze + format + commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"
dart format lib/features/dashboard/application/dashboard_portfolio_kpis_provider.dart test/unit/dashboard_portfolio_kpis_provider_test.dart
flutter analyze lib/features/dashboard/application/dashboard_portfolio_kpis_provider.dart
git add lib/features/dashboard/application/dashboard_portfolio_kpis_provider.dart test/unit/dashboard_portfolio_kpis_provider_test.dart
git commit -m "feat(dashboard): provider KPI patrimoniaux (occupation + patrimoine)"
```

---

### Task 2 : Clés i18n occupation + patrimoine

**Files:**
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`

**Interfaces:**
- Produces (getters sur `AppLocalizations`) : `dashboardKpiOccupancyLabel`, `dashboardKpiOccupancyRented(int occupied, int total)`, `dashboardKpiOccupancyVacant(int count)`, `dashboardKpiOccupancyNone`, `dashboardKpiPatrimonyLabel`, `dashboardKpiPatrimonyAtPurchase`, `dashboardKpiPatrimonyPartial(int withPrice, int total)`, `dashboardKpiPatrimonyNone`.

- [ ] **Step 1 : Ajouter les clés FR** dans `lib/l10n/app_fr.arb` (avant l'accolade finale ; virgule sur la clé précédente ; chaque clé avec description `@key` car le template — `app_en.arb` — exige des descriptions, cf. `arb_parity_test`) :

```json
  "dashboardKpiOccupancyLabel": "Taux d'occupation",
  "dashboardKpiOccupancyRented": "{occupied}/{total} loués",
  "@dashboardKpiOccupancyRented": { "placeholders": { "occupied": { "type": "int" }, "total": { "type": "int" } } },
  "dashboardKpiOccupancyVacant": "{count} vacant",
  "@dashboardKpiOccupancyVacant": { "placeholders": { "count": { "type": "int" } } },
  "dashboardKpiOccupancyNone": "Aucun bien",
  "dashboardKpiPatrimonyLabel": "Patrimoine",
  "dashboardKpiPatrimonyAtPurchase": "à l'achat",
  "dashboardKpiPatrimonyPartial": "sur {withPrice}/{total} biens renseignés",
  "@dashboardKpiPatrimonyPartial": { "placeholders": { "withPrice": { "type": "int" }, "total": { "type": "int" } } },
  "dashboardKpiPatrimonyNone": "Renseignez le prix d'achat"
```

- [ ] **Step 2 : Ajouter les mêmes clés EN** dans `lib/l10n/app_en.arb` — **avec** un bloc `@key` portant une `description` pour CHAQUE nouvelle clé (le template exige les descriptions ; les placeholders identiques à FR) :

```json
  "dashboardKpiOccupancyLabel": "Occupancy",
  "@dashboardKpiOccupancyLabel": { "description": "Dashboard KPI: occupancy rate label" },
  "dashboardKpiOccupancyRented": "{occupied}/{total} rented",
  "@dashboardKpiOccupancyRented": { "description": "Dashboard KPI: rented/total subtitle", "placeholders": { "occupied": { "type": "int" }, "total": { "type": "int" } } },
  "dashboardKpiOccupancyVacant": "{count} vacant",
  "@dashboardKpiOccupancyVacant": { "description": "Dashboard KPI: vacant count", "placeholders": { "count": { "type": "int" } } },
  "dashboardKpiOccupancyNone": "No property",
  "@dashboardKpiOccupancyNone": { "description": "Dashboard KPI: occupancy empty state" },
  "dashboardKpiPatrimonyLabel": "Portfolio value",
  "@dashboardKpiPatrimonyLabel": { "description": "Dashboard KPI: portfolio value label" },
  "dashboardKpiPatrimonyAtPurchase": "at purchase",
  "@dashboardKpiPatrimonyAtPurchase": { "description": "Dashboard KPI: patrimony subtitle (purchase-cost basis)" },
  "dashboardKpiPatrimonyPartial": "on {withPrice}/{total} properties with price",
  "@dashboardKpiPatrimonyPartial": { "description": "Dashboard KPI: patrimony partial-data subtitle", "placeholders": { "withPrice": { "type": "int" }, "total": { "type": "int" } } },
  "dashboardKpiPatrimonyNone": "Add purchase prices",
  "@dashboardKpiPatrimonyNone": { "description": "Dashboard KPI: patrimony empty state" }
```

> NOTE : `l10n.yaml` a `template-arb-file: app_en.arb` — c'est `app_en.arb` qui doit porter les descriptions `@key`. Le FR peut porter ou non les descriptions (les blocs `@` sont exclus du contrôle de parité des clés). Garder les mêmes noms de clés et les mêmes placeholders des deux côtés.

- [ ] **Step 3 : Régénérer + vérifier**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter gen-l10n && flutter analyze lib/l10n/app_localizations.dart && flutter test test/l10n/arb_parity_test.dart`
Expected: génération OK, analyze clean, `arb_parity_test` vert (parité clés FR/EN + descriptions présentes sur le template).

- [ ] **Step 4 : Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"
git add lib/l10n/app_fr.arb lib/l10n/app_en.arb
git commit -m "i18n(dashboard): clés KPI occupation + patrimoine"
```

---

### Task 3 : Refonte de `KpiGrid` + mise à jour des tests

**Files:**
- Modify: `lib/features/dashboard/presentation/widgets/kpi_grid.dart`
- Modify: `test/widget/dashboard_page_test.dart` (groupe KPI : lignes ~268-271 et ~386-456)
- Test (nouveau, ciblé) : `test/widget/kpi_grid_test.dart`

**Interfaces:**
- Consumes: `dashboardPortfolioKpisProvider` (Task 1) → `AsyncValue<PortfolioKpis>` ; `PortfolioKpis` (getters `hasProperties`, `vacant`, `occupancyPercent`, `hasAnyPrice`, champs `patrimoineCents`, `propertiesWithPrice`, `total`) ; clés i18n (Task 2) ; `snapshot.docs` (`DocsPendingKpi.count`) ; `KpiCard`.

- [ ] **Step 1 : Test ciblé qui échoue** — nouvelle grille (occupation/patrimoine/docs), cas nominal + dégradé

```dart
// test/widget/kpi_grid_test.dart
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/kpi_grid.dart';
import 'package:easyrent/features/properties/application/properties_list_provider.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakePropsNotifier extends PropertiesListItemsNotifier {
  _FakePropsNotifier(this._items);
  final List<PropertyListItem> _items;
  @override
  Future<List<PropertyListItem>> build() async => _items;
}

PropertyListItem _prop({String? activeLeaseId, int? price}) => PropertyListItem(
  property: Property(
    id: 'p${activeLeaseId ?? price}',
    landlordId: 'lord1',
    label: 'Bien',
    addressStreet: '1 rue',
    addressPostalCode: '75001',
    addressCity: 'Paris',
    purchasePriceCents: price,
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  ),
  activeLeaseId: activeLeaseId,
);

DashboardSnapshot _snapshot() => const DashboardSnapshot(
  loyers: LoyersMoisKpi(encaissedCents: 0, dueCents: 0),
  retards: RetardsKpi(count: 0),
  renouvellements: RenouvellementsKpi(count: 0),
  docs: DocsPendingKpi(count: 2),
  activity: [],
  isOnboarding: false,
);

Widget _wrap(List<PropertyListItem> items) => ProviderScope(
  overrides: [
    propertiesListItemsProvider.overrideWith(() => _FakePropsNotifier(items)),
  ],
  child: MaterialApp.router(
    theme: AppTheme.light,
    routerConfig: GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => Scaffold(body: KpiGrid(snapshot: _snapshot()))),
      GoRoute(path: '/properties', builder: (_, __) => const Scaffold(body: Text('properties'))),
    ]),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
  ),
);

void main() {
  testWidgets('affiche occupation, patrimoine, docs — plus les anciens KPI', (tester) async {
    await tester.pumpWidget(_wrap([
      _prop(activeLeaseId: 'l1', price: 11800000),
      _prop(activeLeaseId: null, price: 11800000),
    ]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi_occupation')), findsOneWidget);
    expect(find.byKey(const Key('kpi_patrimoine')), findsOneWidget);
    expect(find.byKey(const Key('kpi_docs')), findsOneWidget);
    expect(find.byKey(const Key('kpi_retards')), findsNothing);
    expect(find.byKey(const Key('kpi_renouvellements')), findsNothing);
    expect(find.byKey(const Key('kpi_loyers')), findsNothing);
    // occupation 1/2 = 50 %, patrimoine 236 000 €
    expect(find.textContaining('50'), findsWidgets);
    expect(find.textContaining('236'), findsWidgets);
  });

  testWidgets('occupation tap → /properties', (tester) async {
    await tester.pumpWidget(_wrap([_prop(activeLeaseId: 'l1', price: 11800000)]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kpi_occupation')));
    await tester.pumpAndSettle();
    expect(find.text('properties'), findsOneWidget);
  });

  testWidgets('aucun bien → occupation « — », patrimoine « — »', (tester) async {
    await tester.pumpWidget(_wrap([]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi_occupation')), findsOneWidget);
    expect(find.byKey(const Key('kpi_patrimoine')), findsOneWidget);
  });
}
```

- [ ] **Step 2 : Lancer → échoue**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/widget/kpi_grid_test.dart`
Expected: FAIL (clés `kpi_occupation` / `kpi_patrimoine` absentes).

- [ ] **Step 3 : Réécrire `kpi_grid.dart`**

Remplacer intégralement le corps par un `ConsumerWidget` qui garde la signature (`KpiGrid({super.key, required this.snapshot})`), passe `crossAxisCount` de 4 → **3** au-delà de 900 px, et construit trois cartes :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/money_format.dart';
import '../../application/dashboard_portfolio_kpis_provider.dart';
import '../../domain/dashboard_snapshot.dart';
import 'kpi_card.dart';

/// Grille responsive de 3 KPI : occupation, patrimoine, documents en attente.
///
/// Occupation et patrimoine viennent de [dashboardPortfolioKpisProvider]
/// (dérivé de la liste des biens, zéro requête propre) ; documents vient du
/// [DashboardSnapshot]. Les compteurs loyers/retards/renouvellements ont été
/// retirés — ils font désormais doublon avec le panneau « À traiter / À venir ».
class KpiGrid extends ConsumerWidget {
  const KpiGrid({super.key, required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 900
            ? 3
            : width > 600
            ? 2
            : 1;
        final ratio = width > 900 ? 1.8 : 1.6;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          childAspectRatio: ratio,
          crossAxisSpacing: spacing.md,
          mainAxisSpacing: spacing.md,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: _buildCards(context, ref),
        );
      },
    );
  }

  List<Widget> _buildCards(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;
    final kpis = ref.watch(dashboardPortfolioKpisProvider).valueOrNull;
    final docs = snapshot.docs;

    // --- Occupation ---
    final String occValue;
    final String occSubtitle;
    final Color occColor;
    if (kpis == null || !kpis.hasProperties) {
      occValue = '—';
      occSubtitle = l10n.dashboardKpiOccupancyNone;
      occColor = colors.neutral.solid;
    } else {
      occValue = '${kpis.occupancyPercent} %';
      final rented = l10n.dashboardKpiOccupancyRented(kpis.occupied, kpis.total);
      occSubtitle = kpis.vacant > 0
          ? '$rented · ${l10n.dashboardKpiOccupancyVacant(kpis.vacant)}'
          : rented;
      occColor = kpis.vacant > 0 ? colors.warning.solid : colors.success.solid;
    }

    // --- Patrimoine ---
    final String patValue;
    final String patSubtitle;
    if (kpis == null || !kpis.hasAnyPrice) {
      patValue = '—';
      patSubtitle = l10n.dashboardKpiPatrimonyNone;
    } else {
      patValue = MoneyFormat.formatEurosFromCents(kpis.patrimoineCents);
      patSubtitle = kpis.propertiesWithPrice == kpis.total
          ? l10n.dashboardKpiPatrimonyAtPurchase
          : l10n.dashboardKpiPatrimonyPartial(kpis.propertiesWithPrice, kpis.total);
    }

    final docsColor = docs.count > 0 ? colors.info.solid : colors.neutral.solid;

    return [
      KpiCard(
        key: const Key('kpi_occupation'),
        icon: Icons.meeting_room_outlined,
        label: l10n.dashboardKpiOccupancyLabel,
        value: occValue,
        subtitle: occSubtitle,
        semanticColor: occColor,
        onTap: () => context.go('/properties'),
      ),
      KpiCard(
        key: const Key('kpi_patrimoine'),
        icon: Icons.account_balance_outlined,
        label: l10n.dashboardKpiPatrimonyLabel,
        value: patValue,
        subtitle: patSubtitle,
        semanticColor: colors.neutral.solid,
        onTap: () => context.go('/properties'),
      ),
      // Documents : pas de page globale documents → pas de onTap (pas de chevron).
      KpiCard(
        key: const Key('kpi_docs'),
        icon: Icons.folder_outlined,
        label: l10n.dashboardKpiDocsPendingLabel,
        value: docs.count.toString(),
        subtitle: l10n.dashboardKpiDocsPendingSubtitle,
        semanticColor: docsColor,
      ),
    ];
  }
}
```

> NOTE : `occColor` est déclaré sans type (`final occColor;`) — le remplacer par `final Color occColor;` si l'analyzer le demande, ou déclarer `Color occColor;`. `AppColors` expose `.neutral`, `.success`, `.warning`, `.info` (chacun `StatusColorSet` avec `.solid`) — déjà utilisés dans l'ancien `kpi_grid.dart`.

- [ ] **Step 4 : Lancer le test ciblé → passe**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/widget/kpi_grid_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5 : Mettre à jour `dashboard_page_test.dart`**

Les assertions du groupe KPI référencent les cartes supprimées. Adapter :
- Lignes ~268-271 : remplacer les attentes `kpi_loyers`/`kpi_retards`/`kpi_renouvellements` par `kpi_occupation` + `kpi_patrimoine` ; garder `kpi_docs`.
- Groupe « couleurs sémantiques KpiGrid » (~386-456) : les sous-tests qui tapent `kpi_loyers`/`kpi_retards`/`kpi_renouvellements` ou vérifient la couleur des retards portent sur des cartes disparues → les retirer ou les remplacer par un test de navigation `kpi_occupation` → `/properties`. Ne pas affaiblir : conserver un test de navigation et l'assertion de présence `kpi_docs`.
- Comme `KpiGrid` lit maintenant `propertiesListItemsProvider`, s'assurer que le `ProviderScope` du test le satisfait (le dashboard charge déjà les biens via `PortfolioYieldSection`, mais confirmer que le repository/le provider est fourni ; sinon ajouter un override `propertiesListItemsProvider.overrideWith(() => <fake retournant []>)` comme dans `kpi_grid_test.dart`).

Découvrir précisément les usages :

Run: `export PATH="/opt/homebrew/bin:$PATH" && rg -n "kpi_loyers|kpi_retards|kpi_renouvellements" test/widget/dashboard_page_test.dart`

- [ ] **Step 6 : Suite complète + analyze**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter analyze && flutter test`
Expected: `No issues found` + tous les tests verts. Corriger ce que le retrait des KPI a cassé jusqu'à ce que les deux soient clean.

- [ ] **Step 7 : format + commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"
dart format lib/features/dashboard/presentation/widgets/kpi_grid.dart test/widget/kpi_grid_test.dart test/widget/dashboard_page_test.dart
git add lib/features/dashboard/presentation/widgets/kpi_grid.dart test/widget/kpi_grid_test.dart test/widget/dashboard_page_test.dart
git commit -m "feat(dashboard): grille KPI occupation + patrimoine + docs (retrait des doublons)"
```

---

## Notes d'exécution transverses

- **Vérifier les `required` de `Property`** (freezed) au premier compile des tests : le fixture `_prop`/`_item` doit fournir tous les champs obligatoires (au minimum `id`, `landlordId`, `label`, `addressStreet`, `addressPostalCode`, `addressCity`, `createdAt`, `updatedAt`, `purchasePriceCents` nullable). Ajouter tout autre `required` signalé.
- **`KpiGrid` reste appelé `KpiGrid(snapshot: snapshot)`** dans `dashboard_page.dart` — la signature ne change pas, seul le type de base (`ConsumerWidget`). Aucun changement de site d'appel nécessaire.
- **Ne pas** modifier `KpiCard`, le panneau « À traiter / À venir », ni la section Rentabilité.
- **docs/state/** : après merge, `state-keeper` sur `routes/dashboard.md` (composition KPI) — hors périmètre code.
