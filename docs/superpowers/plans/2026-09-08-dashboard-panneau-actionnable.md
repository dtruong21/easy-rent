# Dashboard — panneau « À traiter / À venir » + graphe repliable — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer le graphe cash-flow du dashboard par un panneau actionnable (encaissements du mois + loyers en retard + baux finissant), et déplacer le graphe plus bas dans une carte repliable fermée par défaut.

**Architecture:** Le panneau dérive ses listes de `leasesListProvider` (même source que l'écran Baux, zéro nouvelle requête Firestore) et son bandeau du `LoyersMoisKpi` déjà présent dans `DashboardSnapshot`. Un helper `isLeaseRenewable` partagé garantit que « baux finissant » du dashboard == filtre « renouvelable » de l'écran Baux. Le graphe `MonthlyCashflowChart` n'est pas réécrit — seulement enveloppé dans un `ExpansionTile` lazy.

**Tech Stack:** Flutter + Riverpod 2.6 (Provider / AsyncNotifierProvider), GoRouter, freezed (existant), fl_chart (existant), i18n `.arb` + `flutter gen-l10n`.

## Global Constraints

- **Zéro nouvelle requête Firestore** : réutiliser `leasesListProvider` et `LoyersMoisKpi` (`DashboardSnapshot.loyers`). Aucun accès `FirebaseFirestore.instance` — de toute façon aucun nouvel accès n'est ajouté.
- **Jetons uniquement** : couleurs via `Theme.of(context).extension<AppColors>() ?? AppColors.light` (`.success` / `.warning` / `.danger`, champ `.solid`/`.onSurface`/`.surface`), espacement via `Theme.of(context).extension<AppSpacing>() ?? const AppSpacing()`, rayons via `AppRadii`. **Jamais** `Colors.*` ni `Color(0x…)`.
- **i18n** : tout libellé via `context.l10n.<clé>` (jamais de chaîne FR/EN en dur), clés ajoutées dans `lib/l10n/app_fr.arb` **et** `lib/l10n/app_en.arb`, puis `flutter gen-l10n`.
- **Montant mensuel dû d'un bail** = `lease.totalAmountCents` (= `rentAmountCents + chargesAmountCents`).
- **Seuil « finissant »** = `endDate.difference(now).inDays < 60` (strict), identique à l'existant.
- **Priorité FEAT-028** : un bail en retard n'apparaît jamais dans « finissant » (late > renewable).
- **Formatage** : montants `MoneyFormat.formatEurosFromCents(int)`, dates `FrenchDate.format(DateTime)`.
- Chaque tâche finit par `flutter analyze` clean + `dart format` sur les fichiers touchés, et commit.

---

### Task 1 : Helper partagé `isLeaseRenewable`

**Files:**
- Create: `lib/features/leases/domain/lease_renewal.dart`
- Modify: `lib/features/leases/application/leases_filter_provider.dart` (remplacer le `_isRenewable` privé)
- Test: `test/unit/lease_renewal_test.dart`

**Interfaces:**
- Produces: `bool isLeaseRenewable(Lease lease, DateTime now)` — `true` si `lease.endDate != null && lease.endDate!.difference(now).inDays < 60`. Ne teste ni le statut ni le retard.

- [ ] **Step 1 : Test qui échoue**

```dart
// test/unit/lease_renewal_test.dart
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_renewal.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:flutter_test/flutter_test.dart';

Lease _lease({DateTime? endDate}) => Lease(
  id: 'l1',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 80000,
  chargesAmountCents: 0,
  nonRecoverableChargesCents: 0,
  startDate: DateTime(2020, 1, 1),
  endDate: endDate,
  status: LeaseStatus.active,
);

void main() {
  final now = DateTime(2026, 9, 8);
  test('endDate dans 30j → renewable', () {
    expect(isLeaseRenewable(_lease(endDate: now.add(const Duration(days: 30))), now), isTrue);
  });
  test('endDate à 60j pile → NON renewable (strict <)', () {
    expect(isLeaseRenewable(_lease(endDate: now.add(const Duration(days: 60))), now), isFalse);
  });
  test('endDate null → non renewable', () {
    expect(isLeaseRenewable(_lease(endDate: null), now), isFalse);
  });
  test('endDate déjà passée → renewable (parité avec le filtre existant)', () {
    expect(isLeaseRenewable(_lease(endDate: now.subtract(const Duration(days: 5))), now), isTrue);
  });
}
```

> NOTE : vérifier les paramètres requis exacts du constructeur `Lease` (freezed) et ajuster `_lease` — il faut au minimum les champs `required`. Les champs ci-dessus correspondent à `lease.dart` (rentAmountCents, chargesAmountCents, nonRecoverableChargesCents, startDate, status). Ajouter les autres `required` s'il en manque au moment de compiler.

- [ ] **Step 2 : Lancer le test → échoue**

Run: `flutter test test/unit/lease_renewal_test.dart`
Expected: FAIL (`lease_renewal.dart` introuvable).

- [ ] **Step 3 : Implémenter le helper**

```dart
// lib/features/leases/domain/lease_renewal.dart
import 'lease.dart';

/// `true` si le bail a une date de fin dans moins de 60 jours.
///
/// Extrait de `leases_filter_provider` pour partager le seuil unique entre
/// l'écran Baux (filtre « renouvelable ») et le dashboard (« baux finissant »).
/// Ne teste PAS le statut ni le retard : la priorité FEAT-028 (late > renewable
/// > active) reste gérée par l'appelant.
bool isLeaseRenewable(Lease lease, DateTime now) {
  final end = lease.endDate;
  if (end == null) return false;
  return end.difference(now).inDays < 60;
}
```

- [ ] **Step 4 : Refactor `leases_filter_provider.dart`**

Remplacer la fonction privée `_isRenewable(...)` par un appel à `isLeaseRenewable(...)`. Ajouter l'import `import '../domain/lease_renewal.dart';` et supprimer la définition locale `bool _isRenewable(Lease lease, DateTime now) {...}`. Les deux usages `_isRenewable(lease, now)` deviennent `isLeaseRenewable(lease, now)`.

- [ ] **Step 5 : Lancer les tests → passent**

Run: `flutter test test/unit/lease_renewal_test.dart test/widget/leases_card_view_test.dart`
Expected: PASS (le refactor ne change pas le comportement du filtre).

- [ ] **Step 6 : analyze + format + commit**

```bash
dart format lib/features/leases/domain/lease_renewal.dart lib/features/leases/application/leases_filter_provider.dart test/unit/lease_renewal_test.dart
flutter analyze lib/features/leases/domain/lease_renewal.dart lib/features/leases/application/leases_filter_provider.dart
git add lib/features/leases/domain/lease_renewal.dart lib/features/leases/application/leases_filter_provider.dart test/unit/lease_renewal_test.dart
git commit -m "refactor(leases): helper partagé isLeaseRenewable (seuil 60j unique)"
```

---

### Task 2 : Modèle + provider des items d'action du dashboard

**Files:**
- Create: `lib/features/dashboard/application/dashboard_action_items_provider.dart`
- Test: `test/unit/dashboard_action_items_provider_test.dart`

**Interfaces:**
- Consumes: `leasesListProvider` (`AsyncNotifierProvider<LeasesListNotifier, List<LeaseListItem>>`), `LeaseListItem` (champs `lease`, `propertyName`, `tenantDisplayName`, `isLate`), `isLeaseRenewable` (Task 1), `LeaseStatus`.
- Produces:
  - `class DashboardActionItems { final List<LeaseListItem> late; final List<LeaseListItem> ending; bool get isEmpty; }`
  - `final dashboardActionItemsProvider = Provider<AsyncValue<DashboardActionItems>>((ref) {...});`

- [ ] **Step 1 : Test qui échoue**

```dart
// test/unit/dashboard_action_items_provider_test.dart
import 'package:easyrent/features/dashboard/application/dashboard_action_items_provider.dart';
import 'package:easyrent/features/leases/application/leases_list_provider.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLeasesNotifier extends LeasesListNotifier {
  _FakeLeasesNotifier(this._items);
  final List<LeaseListItem> _items;
  @override
  Future<List<LeaseListItem>> build() async => _items;
}

LeaseListItem _item({
  required String id,
  required LeaseStatus status,
  bool isLate = false,
  DateTime? endDate,
}) => LeaseListItem(
  lease: Lease(
    id: id,
    propertyId: 'p1',
    tenantId: 't1',
    rentAmountCents: 80000,
    chargesAmountCents: 0,
    nonRecoverableChargesCents: 0,
    startDate: DateTime(2020, 1, 1),
    endDate: endDate,
    status: status,
  ),
  propertyName: 'Bien $id',
  tenantDisplayName: 'Loc $id',
  isLate: isLate,
);

void main() {
  final soon = DateTime.now().add(const Duration(days: 20));
  final far = DateTime.now().add(const Duration(days: 200));

  ProviderContainer containerWith(List<LeaseListItem> items) => ProviderContainer(
    overrides: [
      leasesListProvider.overrideWith(() => _FakeLeasesNotifier(items)),
    ],
  );

  test('partitionne retards et baux finissant, exclut terminés', () async {
    final c = containerWith([
      _item(id: 'late', status: LeaseStatus.active, isLate: true, endDate: soon),
      _item(id: 'ending', status: LeaseStatus.active, endDate: soon),
      _item(id: 'active_far', status: LeaseStatus.active, endDate: far),
      _item(id: 'terminated', status: LeaseStatus.terminated, endDate: soon),
    ]);
    addTearDown(c.dispose);
    // Laisse le leasesListProvider se résoudre.
    await c.read(leasesListProvider.future);

    final res = c.read(dashboardActionItemsProvider).value!;
    expect(res.late.map((i) => i.lease.id), ['late']);
    expect(res.ending.map((i) => i.lease.id), ['ending']); // pas 'late' (déjà en retard), pas 'terminated', pas 'active_far'
    expect(res.isEmpty, isFalse);
  });

  test('aucun item pertinent → isEmpty', () async {
    final c = containerWith([
      _item(id: 'active_far', status: LeaseStatus.active, endDate: far),
    ]);
    addTearDown(c.dispose);
    await c.read(leasesListProvider.future);
    expect(c.read(dashboardActionItemsProvider).value!.isEmpty, isTrue);
  });
}
```

- [ ] **Step 2 : Lancer → échoue**

Run: `flutter test test/unit/dashboard_action_items_provider_test.dart`
Expected: FAIL (provider/modèle introuvables).

- [ ] **Step 3 : Implémenter modèle + provider**

```dart
// lib/features/dashboard/application/dashboard_action_items_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leases/application/leases_list_provider.dart';
import '../../leases/domain/lease_list_item.dart';
import '../../leases/domain/lease_renewal.dart';
import '../../leases/domain/lease_status.dart';

/// Items actionnables dérivés de la liste des baux, pour le panneau
/// « À traiter / À venir » du dashboard. Aucune requête propre : dérive
/// [leasesListProvider] (même source que l'écran Baux).
class DashboardActionItems {
  const DashboardActionItems({required this.late, required this.ending});

  /// Baux actifs en retard de paiement (FEAT-028).
  final List<LeaseListItem> late;

  /// Baux actifs, non en retard, dont la date de fin est < 60 j.
  final List<LeaseListItem> ending;

  bool get isEmpty => late.isEmpty && ending.isEmpty;
}

/// Priorité FEAT-028 : late > renewable. Un bail en retard n'est jamais dans
/// [DashboardActionItems.ending].
final dashboardActionItemsProvider = Provider<AsyncValue<DashboardActionItems>>((
  ref,
) {
  final asyncLeases = ref.watch(leasesListProvider);
  final now = DateTime.now();
  return asyncLeases.whenData((leases) {
    final late = leases
        .where((i) => i.lease.status == LeaseStatus.active && i.isLate)
        .toList();
    final ending = leases
        .where(
          (i) =>
              i.lease.status == LeaseStatus.active &&
              !i.isLate &&
              isLeaseRenewable(i.lease, now),
        )
        .toList();
    return DashboardActionItems(late: late, ending: ending);
  });
});
```

- [ ] **Step 4 : Lancer → passe**

Run: `flutter test test/unit/dashboard_action_items_provider_test.dart`
Expected: PASS.

- [ ] **Step 5 : analyze + format + commit**

```bash
dart format lib/features/dashboard/application/dashboard_action_items_provider.dart test/unit/dashboard_action_items_provider_test.dart
flutter analyze lib/features/dashboard/application/dashboard_action_items_provider.dart
git add lib/features/dashboard/application/dashboard_action_items_provider.dart test/unit/dashboard_action_items_provider_test.dart
git commit -m "feat(dashboard): provider dérivé des items d'action (retards + baux finissant)"
```

---

### Task 3 : Clés i18n du panneau

**Files:**
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Generated: `lib/l10n/app_localizations*.dart` (via `flutter gen-l10n`)

**Interfaces:**
- Produces (getters sur `AppLocalizations`, accès `context.l10n.<clé>`) :
  `dashboardActionPanelTitle`, `dashboardActionLateSectionTitle`, `dashboardActionEndingSectionTitle`, `dashboardActionLateBadge`, `dashboardActionEndingDate(String date)`, `dashboardActionAllClear`, `dashboardActionViewAll(int count)`, `dashboardActionDetailUnavailable`, `dashboardCollectionTitle`, `dashboardCollectionSummary(String collected, String due)`, `dashboardCollectionOutstanding(String amount)`, `dashboardCollectionAllPaid`, `dashboardCashflowCollapsibleTitle`, `dashboardCashflowCollapsibleSubtitle`.

- [ ] **Step 1 : Ajouter les clés FR** dans `lib/l10n/app_fr.arb` (avant l'accolade fermante finale ; garder une virgule sur la clé précédente) :

```json
  "dashboardActionPanelTitle": "À traiter / À venir",
  "dashboardActionLateSectionTitle": "Loyers en retard",
  "dashboardActionEndingSectionTitle": "Baux finissant bientôt",
  "dashboardActionLateBadge": "en retard",
  "dashboardActionEndingDate": "Fin le {date}",
  "@dashboardActionEndingDate": { "placeholders": { "date": { "type": "String" } } },
  "dashboardActionAllClear": "Tout est à jour",
  "dashboardActionViewAll": "Voir tout ({count})",
  "@dashboardActionViewAll": { "placeholders": { "count": { "type": "int" } } },
  "dashboardActionDetailUnavailable": "Détail indisponible",
  "dashboardCollectionTitle": "Encaissements du mois",
  "dashboardCollectionSummary": "{collected} encaissés sur {due} attendus",
  "@dashboardCollectionSummary": { "placeholders": { "collected": { "type": "String" }, "due": { "type": "String" } } },
  "dashboardCollectionOutstanding": "{amount} restant dû",
  "@dashboardCollectionOutstanding": { "placeholders": { "amount": { "type": "String" } } },
  "dashboardCollectionAllPaid": "Tout est encaissé ce mois",
  "dashboardCashflowCollapsibleTitle": "Cash-flow mensuel — détail",
  "dashboardCashflowCollapsibleSubtitle": "Surtout utile si vous saisissez crédit et dépenses."
```

- [ ] **Step 2 : Ajouter les mêmes clés EN** dans `lib/l10n/app_en.arb` (mêmes noms/placeholders, valeurs traduites) :

```json
  "dashboardActionPanelTitle": "To handle / Upcoming",
  "dashboardActionLateSectionTitle": "Late rents",
  "dashboardActionEndingSectionTitle": "Leases ending soon",
  "dashboardActionLateBadge": "late",
  "dashboardActionEndingDate": "Ends {date}",
  "@dashboardActionEndingDate": { "placeholders": { "date": { "type": "String" } } },
  "dashboardActionAllClear": "All up to date",
  "dashboardActionViewAll": "View all ({count})",
  "@dashboardActionViewAll": { "placeholders": { "count": { "type": "int" } } },
  "dashboardActionDetailUnavailable": "Details unavailable",
  "dashboardCollectionTitle": "This month's collection",
  "dashboardCollectionSummary": "{collected} collected of {due} expected",
  "@dashboardCollectionSummary": { "placeholders": { "collected": { "type": "String" }, "due": { "type": "String" } } },
  "dashboardCollectionOutstanding": "{amount} outstanding",
  "@dashboardCollectionOutstanding": { "placeholders": { "amount": { "type": "String" } } },
  "dashboardCollectionAllPaid": "Everything collected this month",
  "dashboardCashflowCollapsibleTitle": "Monthly cash flow — details",
  "dashboardCashflowCollapsibleSubtitle": "Most useful when you record loan and expenses."
```

- [ ] **Step 3 : Régénérer + vérifier compile**

Run: `flutter gen-l10n && flutter analyze lib/l10n/app_localizations.dart`
Expected: génération sans erreur ; les getters ci-dessus existent.

- [ ] **Step 4 : Commit**

```bash
git add lib/l10n/app_fr.arb lib/l10n/app_en.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_fr.dart lib/l10n/app_localizations_en.dart
git commit -m "i18n(dashboard): clés du panneau actionnable + graphe repliable"
```

---

### Task 4 : Widget `ActionItemsPanel`

**Files:**
- Create: `lib/features/dashboard/presentation/widgets/action_items_panel.dart`
- Test: `test/widget/action_items_panel_test.dart`

**Interfaces:**
- Consumes: `dashboardActionItemsProvider` (Task 2), `LoyersMoisKpi` (`encaissedCents`, `dueCents`), `MoneyFormat.formatEurosFromCents`, `FrenchDate.format`, `context.l10n` (Task 3), `context.go`.
- Produces: `class ActionItemsPanel extends ConsumerWidget` — constructeur `const ActionItemsPanel({super.key, required this.loyers})`, champ `final LoyersMoisKpi loyers;`.

**Comportement** : carte (surface + border + radius) contenant, de haut en bas : titre `dashboardActionPanelTitle` ; bandeau encaissements ; liste retards (max 3 + « voir tout ») ; liste baux finissant (max 3 + « voir tout ») ; sinon état « tout est à jour ». Clés de test : panneau `Key('dashboard_action_panel')`, ligne retard `Key('action_late_<leaseId>')` → `context.go('/leases?filter=late')`, ligne finissant `Key('action_ending_<leaseId>')` → `context.go('/leases?filter=renewable')`, état vide `Key('action_items_empty')`, voir-tout `Key('action_late_view_all')` / `Key('action_ending_view_all')`.

- [ ] **Step 1 : Tests qui échouent**

```dart
// test/widget/action_items_panel_test.dart
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/dashboard/application/dashboard_action_items_provider.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/action_items_panel.dart';
import 'package:easyrent/features/leases/application/leases_list_provider.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeLeasesNotifier extends LeasesListNotifier {
  _FakeLeasesNotifier(this._items);
  final List<LeaseListItem> _items;
  @override
  Future<List<LeaseListItem>> build() async => _items;
}

LeaseListItem _item({required String id, bool isLate = false, DateTime? endDate}) =>
    LeaseListItem(
      lease: Lease(
        id: id, propertyId: 'p', tenantId: 't',
        rentAmountCents: 80000, chargesAmountCents: 0, nonRecoverableChargesCents: 0,
        startDate: DateTime(2020, 1, 1), endDate: endDate, status: LeaseStatus.active,
      ),
      propertyName: 'Bien $id', tenantDisplayName: 'Loc $id', isLate: isLate,
    );

Widget _wrap(List<LeaseListItem> items, {required GoRouter router}) {
  return ProviderScope(
    overrides: [leasesListProvider.overrideWith(() => _FakeLeasesNotifier(items))],
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      locale: const Locale('fr'),
      supportedLocales: supportedLocales,
    ),
  );
}

GoRouter _router() => GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const Scaffold(
    body: ActionItemsPanel(loyers: LoyersMoisKpi(encaissedCents: 60000, dueCents: 80000)),
  )),
  GoRoute(path: '/leases', builder: (_, s) => Scaffold(body: Text('leases ${s.uri.query}'))),
]);

void main() {
  testWidgets('retard → ligne + tap va vers filter=late', (tester) async {
    final soon = DateTime.now().add(const Duration(days: 20));
    await tester.pumpWidget(_wrap([_item(id: 'A', isLate: true, endDate: soon)], router: _router()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard_action_panel')), findsOneWidget);
    expect(find.byKey(const Key('action_late_A')), findsOneWidget);
    await tester.tap(find.byKey(const Key('action_late_A')));
    await tester.pumpAndSettle();
    expect(find.text('leases filter=late'), findsOneWidget);
  });

  testWidgets('bail finissant → ligne + tap va vers filter=renewable', (tester) async {
    final soon = DateTime.now().add(const Duration(days: 20));
    await tester.pumpWidget(_wrap([_item(id: 'B', endDate: soon)], router: _router()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action_ending_B')), findsOneWidget);
    await tester.tap(find.byKey(const Key('action_ending_B')));
    await tester.pumpAndSettle();
    expect(find.text('leases filter=renewable'), findsOneWidget);
  });

  testWidgets('aucun item → état « tout est à jour »', (tester) async {
    final far = DateTime.now().add(const Duration(days: 300));
    await tester.pumpWidget(_wrap([_item(id: 'C', endDate: far)], router: _router()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action_items_empty')), findsOneWidget);
  });
}
```

- [ ] **Step 2 : Lancer → échoue**

Run: `flutter test test/widget/action_items_panel_test.dart`
Expected: FAIL (`ActionItemsPanel` introuvable).

- [ ] **Step 3 : Implémenter le widget**

```dart
// lib/features/dashboard/presentation/widgets/action_items_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../../leases/domain/lease_list_item.dart';
import '../../application/dashboard_action_items_provider.dart';
import '../../domain/dashboard_kpi.dart';

/// Panneau « À traiter / À venir » : encaissements du mois + loyers en retard
/// + baux finissant. Remplace le graphe cash-flow à son emplacement.
class ActionItemsPanel extends ConsumerWidget {
  const ActionItemsPanel({super.key, required this.loyers});

  final LoyersMoisKpi loyers;

  static const _maxRows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final radii = theme.extension<AppRadii>() ?? const AppRadii();
    final l10n = context.l10n;
    final async = ref.watch(dashboardActionItemsProvider);
    final items = async.valueOrNull;

    return Container(
      key: const Key('dashboard_action_panel'),
      padding: EdgeInsets.all(spacing.cardPaddingStandard),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.dashboardActionPanelTitle, style: theme.textTheme.titleMedium),
          SizedBox(height: spacing.md),
          _CollectionBanner(loyers: loyers),
          if (items != null) ...[
            if (items.late.isNotEmpty) ...[
              SizedBox(height: spacing.lg),
              _Section(
                title: l10n.dashboardActionLateSectionTitle,
                rows: items.late,
                keyPrefix: 'action_late',
                viewAllKey: 'action_late_view_all',
                onTapRoute: '/leases?filter=late',
                trailing: (ctx) => _Badge(
                  label: l10n.dashboardActionLateBadge,
                  color: (theme.extension<AppColors>() ?? AppColors.light).danger,
                ),
                subtitle: (i) => MoneyFormat.formatEurosFromCents(i.lease.totalAmountCents),
              ),
            ],
            if (items.ending.isNotEmpty) ...[
              SizedBox(height: spacing.lg),
              _Section(
                title: l10n.dashboardActionEndingSectionTitle,
                rows: items.ending,
                keyPrefix: 'action_ending',
                viewAllKey: 'action_ending_view_all',
                onTapRoute: '/leases?filter=renewable',
                trailing: null,
                subtitle: (i) => i.lease.endDate != null
                    ? l10n.dashboardActionEndingDate(FrenchDate.format(i.lease.endDate!))
                    : '',
              ),
            ],
            if (items.isEmpty)
              Padding(
                key: const Key('action_items_empty'),
                padding: EdgeInsets.only(top: spacing.md),
                child: Text(
                  l10n.dashboardActionAllClear,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: (theme.extension<AppColors>() ?? AppColors.light).success.solid,
                  ),
                ),
              ),
          ] else if (async.hasError)
            Padding(
              padding: EdgeInsets.only(top: spacing.md),
              child: Text(
                l10n.dashboardActionDetailUnavailable,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.only(top: spacing.md),
              child: const Center(child: SizedBox(
                height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2),
              )),
            ),
        ],
      ),
    );
  }
}

class _CollectionBanner extends StatelessWidget {
  const _CollectionBanner({required this.loyers});
  final LoyersMoisKpi loyers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = theme.extension<AppColors>() ?? AppColors.light;
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final due = loyers.dueCents;
    final collected = loyers.encaissedCents;
    final outstanding = (due - collected) > 0 ? (due - collected) : 0;
    final ratio = due > 0 ? (collected / due).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashboardCollectionTitle, style: theme.textTheme.labelLarge),
        SizedBox(height: spacing.xs),
        Text(
          l10n.dashboardCollectionSummary(
            MoneyFormat.formatEurosFromCents(collected),
            MoneyFormat.formatEurosFromCents(due),
          ),
          style: theme.textTheme.bodyMedium,
        ),
        if (due > 0) ...[
          SizedBox(height: spacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: outstanding > 0 ? colors.warning.solid : colors.success.solid,
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            outstanding > 0
                ? l10n.dashboardCollectionOutstanding(
                    MoneyFormat.formatEurosFromCents(outstanding))
                : l10n.dashboardCollectionAllPaid,
            style: theme.textTheme.bodySmall?.copyWith(
              color: outstanding > 0 ? colors.warning.solid : colors.success.solid,
            ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.rows,
    required this.keyPrefix,
    required this.viewAllKey,
    required this.onTapRoute,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final List<LeaseListItem> rows;
  final String keyPrefix;
  final String viewAllKey;
  final String onTapRoute;
  final String Function(LeaseListItem) subtitle;
  final Widget Function(BuildContext)? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;
    final shown = rows.take(ActionItemsPanel._maxRows).toList();
    final overflow = rows.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        )),
        SizedBox(height: spacing.xs),
        ...shown.map((i) => ListTile(
          key: Key('${keyPrefix}_${i.lease.id}'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('${i.tenantDisplayName} · ${i.propertyName}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle(i), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: trailing?.call(context),
          onTap: () => context.go(onTapRoute),
        )),
        if (overflow > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: Key(viewAllKey),
              onPressed: () => context.go(onTapRoute),
              child: Text(l10n.dashboardActionViewAll(rows.length)),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final StatusColorSet color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color.onSurface, fontWeight: FontWeight.w600,
      )),
    );
  }
}
```

> NOTE : vérifier les champs disponibles de `StatusColorSet` (`surface`, `onSurface`, `solid`, `onSolid` — cf. `app_colors.dart`). Si `surfaceContainerHighest` n'existe pas sur le `ColorScheme` du projet, utiliser `theme.colorScheme.surfaceContainerHigh`.

- [ ] **Step 4 : Lancer → passe**

Run: `flutter test test/widget/action_items_panel_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5 : analyze + format + commit**

```bash
dart format lib/features/dashboard/presentation/widgets/action_items_panel.dart test/widget/action_items_panel_test.dart
flutter analyze lib/features/dashboard/presentation/widgets/action_items_panel.dart
git add lib/features/dashboard/presentation/widgets/action_items_panel.dart test/widget/action_items_panel_test.dart
git commit -m "feat(dashboard): panneau actionnable « À traiter / À venir »"
```

---

### Task 5 : Graphe cash-flow repliable

**Files:**
- Create: `lib/features/dashboard/presentation/widgets/collapsible_cashflow_section.dart`
- Test: `test/widget/collapsible_cashflow_section_test.dart`

**Interfaces:**
- Consumes: `MonthlyCashflowChart` (widget existant, inchangé), `context.l10n` (Task 3).
- Produces: `class CollapsibleCashflowSection extends StatelessWidget` — `const CollapsibleCashflowSection({super.key})`.

- [ ] **Step 1 : Test qui échoue**

```dart
// test/widget/collapsible_cashflow_section_test.dart
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/collapsible_cashflow_section.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/monthly_cashflow_chart.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap() => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: const Scaffold(body: SingleChildScrollView(child: CollapsibleCashflowSection())),
  ),
);

void main() {
  testWidgets('fermé par défaut → chart non construit', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    expect(find.byType(MonthlyCashflowChart), findsNothing);
    expect(find.text('Cash-flow mensuel — détail'), findsOneWidget);
  });

  testWidgets('déplié → chart construit', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    await tester.tap(find.text('Cash-flow mensuel — détail'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthlyCashflowChart), findsOneWidget);
  });
}
```

- [ ] **Step 2 : Lancer → échoue**

Run: `flutter test test/widget/collapsible_cashflow_section_test.dart`
Expected: FAIL (`CollapsibleCashflowSection` introuvable).

- [ ] **Step 3 : Implémenter**

```dart
// lib/features/dashboard/presentation/widgets/collapsible_cashflow_section.dart
import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import 'monthly_cashflow_chart.dart';

/// Enveloppe repliable (fermée par défaut) autour de [MonthlyCashflowChart].
///
/// `maintainState: false` → l'enfant (et donc `monthlyCashflowProvider`) n'est
/// construit qu'au premier dépliage : le graphe ne charge rien tant que la
/// carte reste fermée.
class CollapsibleCashflowSection extends StatelessWidget {
  const CollapsibleCashflowSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radii = theme.extension<AppRadii>() ?? const AppRadii();
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Retire les traits par défaut de l'ExpansionTile pour coller à la carte.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('cashflow_expansion'),
          initiallyExpanded: false,
          maintainState: false,
          tilePadding: EdgeInsets.symmetric(horizontal: spacing.lg, vertical: spacing.xs),
          title: Text(l10n.dashboardCashflowCollapsibleTitle, style: theme.textTheme.titleSmall),
          subtitle: Text(
            l10n.dashboardCashflowCollapsibleSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          childrenPadding: EdgeInsets.fromLTRB(spacing.lg, 0, spacing.lg, spacing.lg),
          children: const [MonthlyCashflowChart()],
        ),
      ),
    );
  }
}
```

> NOTE : `dividerColor: Colors.transparent` sur un `Theme` local est admis (retrait d'un trait, pas une couleur de marque). Si le linter du projet interdit tout `Colors.*` même ici, remplacer par `theme.colorScheme.surface`.

- [ ] **Step 4 : Lancer → passe**

Run: `flutter test test/widget/collapsible_cashflow_section_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5 : analyze + format + commit**

```bash
dart format lib/features/dashboard/presentation/widgets/collapsible_cashflow_section.dart test/widget/collapsible_cashflow_section_test.dart
flutter analyze lib/features/dashboard/presentation/widgets/collapsible_cashflow_section.dart
git add lib/features/dashboard/presentation/widgets/collapsible_cashflow_section.dart test/widget/collapsible_cashflow_section_test.dart
git commit -m "feat(dashboard): carte repliable autour du graphe cash-flow"
```

---

### Task 6 : Câblage dans le dashboard

**Files:**
- Modify: `lib/features/dashboard/presentation/dashboard_page.dart` (le `Column` de `_DataView`, ~lignes 200-214)
- Test: `test/widget/dashboard_page_test.dart` (fichier existant — vérifier le nom exact ; sinon `dashboard_layout_test.dart`)

**Interfaces:**
- Consumes: `ActionItemsPanel` (Task 4), `CollapsibleCashflowSection` (Task 5), `snapshot.loyers` (`LoyersMoisKpi`).

- [ ] **Step 1 : Modifier l'ordre des sections**

Dans `_DataView.build`, remplacer :

```dart
        const PortfolioYieldSection(),
        SizedBox(height: spacing.xl),
        const MonthlyCashflowChart(),
        SizedBox(height: spacing.xl),
        RecentActivitySection(items: snapshot.activity),
```

par :

```dart
        const PortfolioYieldSection(),
        SizedBox(height: spacing.xl),
        ActionItemsPanel(loyers: snapshot.loyers),
        SizedBox(height: spacing.xl),
        const CollapsibleCashflowSection(),
        SizedBox(height: spacing.xl),
        RecentActivitySection(items: snapshot.activity),
```

Ajouter les imports :
```dart
import 'widgets/action_items_panel.dart';
import 'widgets/collapsible_cashflow_section.dart';
```
Retirer l'import direct `import 'widgets/monthly_cashflow_chart.dart';` **seulement s'il n'est plus référencé** dans ce fichier (il ne l'est plus après le remplacement).

- [ ] **Step 2 : Mettre à jour les tests du dashboard**

Chercher les tests qui asssertent la présence directe de `MonthlyCashflowChart` dans le dashboard :

Run: `rg -n "MonthlyCashflowChart|monthly_cashflow" test/`

Pour chaque test qui vérifiait `find.byType(MonthlyCashflowChart)` sur le dashboard sans déplier : soit le remplacer par `find.byType(CollapsibleCashflowSection)`, soit déplier d'abord (`tester.tap(find.text('Cash-flow mensuel — détail'))`). Ajouter, si pertinent, une assertion `find.byType(ActionItemsPanel)` présente.

- [ ] **Step 3 : Lancer les tests du dashboard**

Run: `flutter test test/widget/ -name dashboard` (ou lancer les fichiers dashboard détectés à l'étape 2)
Expected: PASS. Corriger les assertions cassées par le réordonnancement.

- [ ] **Step 4 : Suite complète + analyze**

Run: `flutter analyze && flutter test`
Expected: `No issues found` + tous les tests verts.

- [ ] **Step 5 : Commit**

```bash
git add lib/features/dashboard/presentation/dashboard_page.dart test/
git commit -m "feat(dashboard): panneau actionnable à la place du graphe, graphe repliable dessous"
```

---

## Notes d'exécution transverses

- **Vérifier les `required` de `Lease`** (freezed) au premier compile des tests : les helpers `_lease`/`_item` doivent fournir tous les champs obligatoires. Le champ loyer est `rentAmountCents`, les charges `chargesAmountCents`, part non récupérable `nonRecoverableChargesCents`, plus `id`, `propertyId`, `tenantId`, `startDate`, `status`. Ajouter tout autre `required` signalé par le compilateur.
- **`StatusColorSet`** expose `surface`, `onSurface`, `solid`, `onSolid` (cf. `lib/core/ui/theme/app_colors.dart`).
- **Ne pas** modifier `MonthlyCashflowChart` ni ses providers.
- **docs/state/** : après merge, rafraîchir `docs/state/routes/dashboard.md` (nouvelle composition) — hors périmètre code, à faire via `state-keeper`/`/refresh-state`.
