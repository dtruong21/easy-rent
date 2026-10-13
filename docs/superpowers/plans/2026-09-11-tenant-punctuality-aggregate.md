# Fiche locataire — ponctualité de paiement agrégée — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sur la fiche locataire, afficher un indicateur factuel de ponctualité de paiement agrégé sur tous les baux du locataire, et la ponctualité par bail (#175) sur chaque ligne de la section « Baux ».

**Architecture:** Réutilisation maximale de #175 : le modèle `PaymentPunctuality` et `computePaymentPunctuality` sont additifs, donc l'agrégat = somme par bail. On extrait d'abord la présentation de #175 en un widget réutilisable (`PaymentPunctualityView`), puis un widget agrégat (`TenantPunctualityIndicator`) qui somme la ponctualité des baux du locataire et rend cette vue. La liste des baux du locataire est exposée via un nouveau `tenantLeasesProvider` (thin wrapper Riverpod sur `listLeasesForTenant`) consommé par l'agrégat ; la section « Baux liés » garde son chargement impératif actuel (hors périmètre).

**Tech Stack:** Flutter (web + mobile), Riverpod (`FutureProvider.family`, `FamilyAsyncNotifier`), flutter_test.

## Global Constraints

- **Accès Firestore jamais en direct** : uniquement via `leasePaymentsProvider` et `TenantRepository`. Aucune nouvelle collection, aucune persistance de « score ».
- **Factuel & privé** : le propre historique du locataire ; jamais de score/lettre/étoiles ; **aucune agrégation/classement/liste noire inter-locataires** ; jamais partagé/exporté.
- **% seulement si `total ≥ 3`** (agrégé) ; « à l'heure » = `paidAt ≤ échéance + kDefaultLeaseGraceDays` (5 j).
- **Jetons de design uniquement** (`AppColors` via extension, `AppSpacing`) ; aucune couleur en dur.
- **i18n** : réutiliser les clés `paymentsPunctuality*` existantes (#175). N'ajouter une clé que si un libellé nouveau est réellement nécessaire — aucun prévu.
- **Responsive** via `core/ui/breakpoints.dart` (seuil 600).
- Toolchain : `export PATH="/opt/homebrew/bin:$PATH"` avant tout flutter/dart.
- Commits : chemins EXPLICITES (jamais `git add -A`), message finissant par `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: Helper `combinePaymentPunctuality`

**Files:**
- Modify: `lib/features/payments/domain/payment_punctuality.dart`
- Test: `test/unit/payment_punctuality_test.dart`

**Interfaces:**
- Consumes: `PaymentPunctuality {int total; int onTime;}` (existant).
- Produces: `PaymentPunctuality combinePaymentPunctuality(Iterable<PaymentPunctuality> parts)` — somme `total` et `onTime`.

- [ ] **Step 1: Écrire les tests**

Ajouter dans `test/unit/payment_punctuality_test.dart` :

```dart
group('combinePaymentPunctuality', () {
  test('somme total et onTime sur plusieurs baux', () {
    final combined = combinePaymentPunctuality(const [
      PaymentPunctuality(total: 3, onTime: 2),
      PaymentPunctuality(total: 3, onTime: 3),
    ]);
    expect(combined.total, 6);
    expect(combined.onTime, 5);
    expect(combined.late, 1);
    expect(combined.onTimePercent, 83); // (5/6*100).round()
  });

  test('liste vide → total 0, hasPayments false, percent null', () {
    final combined = combinePaymentPunctuality(const []);
    expect(combined.total, 0);
    expect(combined.hasPayments, isFalse);
    expect(combined.onTimePercent, isNull);
  });

  test('total agrégé < 3 → onTimePercent null', () {
    final combined = combinePaymentPunctuality(const [
      PaymentPunctuality(total: 1, onTime: 1),
      PaymentPunctuality(total: 1, onTime: 0),
    ]);
    expect(combined.total, 2);
    expect(combined.onTimePercent, isNull);
  });
});
```

- [ ] **Step 2: Lancer — échec attendu**

Run: `flutter test test/unit/payment_punctuality_test.dart`
Expected: FAIL — `combinePaymentPunctuality` non défini.

- [ ] **Step 3: Implémenter le helper**

Ajouter dans `payment_punctuality.dart` (après `computePaymentPunctuality`) :

```dart
/// Combine plusieurs [PaymentPunctuality] en un seul (somme additive).
///
/// Utilisé pour agréger la ponctualité d'un locataire sur l'ensemble de ses
/// baux — jamais entre locataires. Les getters dérivés (`late`,
/// `onTimePercent` avec son seuil de 3) s'appliquent au total combiné.
PaymentPunctuality combinePaymentPunctuality(
  Iterable<PaymentPunctuality> parts,
) {
  var total = 0;
  var onTime = 0;
  for (final p in parts) {
    total += p.total;
    onTime += p.onTime;
  }
  return PaymentPunctuality(total: total, onTime: onTime);
}
```

- [ ] **Step 4: Lancer — vert**

Run: `flutter test test/unit/payment_punctuality_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payments/domain/payment_punctuality.dart test/unit/payment_punctuality_test.dart
git commit -m "feat(payments): helper combinePaymentPunctuality (agrégation additive)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Extraire `PaymentPunctualityView` (refactor de présentation)

Extraire la présentation d'un `PaymentPunctuality` (ligne/pill responsive + feuille de détail au tap) en un widget réutilisable, pour que l'agrégat (Task 4) le réutilise sans dupliquer ~130 lignes. Refactor pur : aucun changement de comportement, les clés restent identiques.

**Files:**
- Modify: `lib/features/payments/presentation/widgets/payment_punctuality_indicator.dart`
- Test: `test/widget/payment_punctuality_indicator_test.dart` (doit rester vert, inchangé)

**Interfaces:**
- Consumes: `PaymentPunctuality` (avec `onTime`, `total`, `late`, `onTimePercent`).
- Produces: `class PaymentPunctualityView extends StatelessWidget { const PaymentPunctualityView({super.key, required this.k}); final PaymentPunctuality k; }` — rend la ligne (`Key('payment_punctuality_line')`) ou le pill (`Key('payment_punctuality_pill')`) selon `context.isMobile`, enveloppé dans un `InkWell` (`Key('payment_punctuality_tap')`) ouvrant la feuille (`Key('payment_punctuality_sheet')`). `PaymentPunctualityIndicator` reste inchangé côté API mais délègue son rendu à `PaymentPunctualityView`.

- [ ] **Step 1: Créer `PaymentPunctualityView`**

Dans `payment_punctuality_indicator.dart`, ajouter un widget public `PaymentPunctualityView` qui contient **exactement** l'actuel corps de rendu de `PaymentPunctualityIndicator.build` à partir de la ligne `final tone = ...` (calcul du `tone`, branche `context.isMobile` pill / branche ligne, et le `return InkWell(...)`), plus la méthode `_showDetail` et la classe `_DetailTile` (les déplacer dans/à côté de la view). La view lit `k` depuis son champ (au lieu d'une variable locale). Conserver les mêmes `Key(...)`, jetons (`AppColors`, `AppSpacing`), et clés i18n `paymentsPunctuality*`.

- [ ] **Step 2: Déléguer depuis `PaymentPunctualityIndicator`**

`PaymentPunctualityIndicator.build` devient :

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final payments = ref.watch(leasePaymentsProvider(leaseId)).valueOrNull;
  if (payments == null) return const SizedBox.shrink();
  final k = computePaymentPunctuality(payments, paymentDay: paymentDay);
  if (!k.hasPayments) return const SizedBox.shrink();
  return PaymentPunctualityView(k: k);
}
```

Retirer de `PaymentPunctualityIndicator` les imports devenus inutiles (`breakpoints`, `app_colors`, `app_spacing`, `l10n_extensions`) si `PaymentPunctualityView` les porte désormais ; garder `lease_payments_provider` et `payment_punctuality`.

- [ ] **Step 3: Lancer les tests existants — verts, inchangés**

Run: `flutter test test/widget/payment_punctuality_indicator_test.dart`
Expected: PASS — mêmes clés (`payment_punctuality_pill/line/tap/sheet`), aucun comportement modifié.

- [ ] **Step 4: Analyze**

Run: `flutter analyze`
Expected: No issues found!

- [ ] **Step 5: Commit**

```bash
git add lib/features/payments/presentation/widgets/payment_punctuality_indicator.dart
git commit -m "refactor(payments): extrait PaymentPunctualityView réutilisable

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Projection `payment_day` dans `listLeasesForTenant`

**Files:**
- Modify: `lib/features/tenants/data/tenant_repository.dart` (projection ~lignes 319-330)
- Test: `test/unit/tenant_repository_test.dart` (+ mettre à jour tout fake reconstruisant la projection dans `test/widget/tenant_detail_page_test.dart` et `test/widget/tenant_lease_summary_test.dart`)

**Interfaces:**
- Produces: `listLeasesForTenant` retourne des maps incluant `'payment_day': int` (en plus de `id`, `property_id`, `start_date`, `end_date`, `status`, `rent_amount_cents`).

- [ ] **Step 1: Écrire/mettre à jour le test repo**

Dans `test/unit/tenant_repository_test.dart`, dans le test couvrant `listLeasesForTenant` (là où le bail seedé fixe `paymentDay`), ajouter l'assertion que la map retournée contient `payment_day` égal à la valeur seedée. Si le bail de test ne fixe pas `paymentDay`, l'ajouter au seed (ex. `'paymentDay': 5`) et asserter `leases.first['payment_day'] == 5`.

- [ ] **Step 2: Lancer — échec attendu**

Run: `flutter test test/unit/tenant_repository_test.dart`
Expected: FAIL — `payment_day` absent de la projection.

- [ ] **Step 3: Étendre la projection**

Dans `tenant_repository.dart`, dans le `return {...}` de `listLeasesForTenant`, ajouter la ligne :

```dart
        'payment_day': raw['paymentDay'],
```

(à côté de `'rent_amount_cents': raw['rentAmountCents'],`).

- [ ] **Step 4: Mettre à jour les fakes de widget test**

Dans `test/widget/tenant_detail_page_test.dart` et `test/widget/tenant_lease_summary_test.dart`, tout fake/mock qui construit des maps de baux (pour `listLeasesForTenant` ou passées à `TenantLeaseSummary`) doit inclure `'payment_day': <int>` (ex. `5`) pour rester représentatif. Ne pas modifier d'assertions existantes au-delà de l'ajout du champ.

- [ ] **Step 5: Lancer — vert**

Run: `flutter test test/unit/tenant_repository_test.dart test/widget/tenant_detail_page_test.dart test/widget/tenant_lease_summary_test.dart`
Expected: PASS. Puis `flutter analyze` → No issues found!

- [ ] **Step 6: Commit**

```bash
git add lib/features/tenants/data/tenant_repository.dart test/unit/tenant_repository_test.dart test/widget/tenant_detail_page_test.dart test/widget/tenant_lease_summary_test.dart
git commit -m "feat(tenants): expose payment_day dans listLeasesForTenant

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `tenantLeasesProvider` + `TenantPunctualityIndicator` + insertion en tête de fiche

**Files:**
- Create: `lib/features/tenants/application/tenant_leases_provider.dart`
- Create: `lib/features/tenants/presentation/widgets/tenant_punctuality_indicator.dart`
- Modify: `lib/features/tenants/presentation/tenant_detail_page.dart` (insérer l'agrégat après `_InfoCard`)
- Create: `test/widget/tenant_punctuality_indicator_test.dart`

**Interfaces:**
- Consumes: `combinePaymentPunctuality` (Task 1), `computePaymentPunctuality`/`PaymentPunctuality` (existants), `PaymentPunctualityView` (Task 2), `leasePaymentsProvider` (`FamilyAsyncNotifier<List<Payment>, String>`), `listLeasesForTenant` retournant `payment_day` (Task 3), `tenantRepositoryProvider`.
- Produces: `tenantLeasesProvider` (`FutureProvider.family<List<Map<String,dynamic>>, String>`) ; `TenantPunctualityIndicator({required String tenantId})`.

- [ ] **Step 1: Écrire le test widget**

Créer `test/widget/tenant_punctuality_indicator_test.dart` :

```dart
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/payments/application/lease_payments_provider.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/tenants/application/tenant_leases_provider.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenant_punctuality_indicator.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePayments extends LeasePaymentsNotifier {
  _FakePayments(this._byLease);
  final Map<String, List<Payment>> _byLease;
  @override
  Future<List<Payment>> build(String arg) async => _byLease[arg] ?? const [];
}

Payment _pay({
  required String leaseId,
  required DateTime periodStart,
  required DateTime paidAt,
}) => Payment(
  id: '$leaseId-${periodStart.month}',
  leaseId: leaseId,
  landlordId: 'lord1',
  periodStart: periodStart,
  periodEnd: DateTime(periodStart.year, periodStart.month + 1, 0),
  paidAt: paidAt,
  rentAmountCents: 80000,
  chargesAmountCents: 0,
  createdAt: periodStart,
  updatedAt: periodStart,
);

Widget _wrap({
  required List<Map<String, dynamic>> leases,
  required Map<String, List<Payment>> byLease,
}) => ProviderScope(
  overrides: [
    tenantLeasesProvider('t1').overrideWith((ref) async => leases),
    leasePaymentsProvider.overrideWith(() => _FakePayments(byLease)),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: const Scaffold(
      body: TenantPunctualityIndicator(tenantId: 't1'),
    ),
  ),
);

void main() {
  testWidgets('agrège la ponctualité sur plusieurs baux (large → ligne)', (
    tester,
  ) async {
    // paymentDay=5, échéance = 5 du mois ; à l'heure si paidAt <= 5+5j = 10.
    final onTime = DateTime(2026, 1, 8); // <= 10 janv → à l'heure
    final late = DateTime(2026, 1, 20); // > 10 janv → en retard
    await tester.pumpWidget(_wrap(
      leases: const [
        {'id': 'l1', 'payment_day': 5},
        {'id': 'l2', 'payment_day': 5},
      ],
      byLease: {
        'l1': [
          _pay(leaseId: 'l1', periodStart: DateTime(2026, 1, 1), paidAt: onTime),
          _pay(leaseId: 'l1', periodStart: DateTime(2026, 2, 1), paidAt: DateTime(2026, 2, 8)),
        ],
        'l2': [
          _pay(leaseId: 'l2', periodStart: DateTime(2026, 1, 1), paidAt: late),
        ],
      },
    ));
    await tester.pumpAndSettle();
    // 3 paiements, 2 à l'heure → ligne complète visible (largeur test par défaut ≥ 600).
    expect(find.byKey(const Key('payment_punctuality_line')), findsOneWidget);
    expect(find.textContaining('2/3'), findsOneWidget);
  });

  testWidgets('aucun paiement sur les baux → rien', (tester) async {
    await tester.pumpWidget(_wrap(
      leases: const [
        {'id': 'l1', 'payment_day': 5},
      ],
      byLease: const {'l1': []},
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_line')), findsNothing);
    expect(find.byKey(const Key('payment_punctuality_pill')), findsNothing);
  });

  testWidgets('aucun bail → rien', (tester) async {
    await tester.pumpWidget(_wrap(leases: const [], byLease: const {}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_tap')), findsNothing);
  });
}
```

- [ ] **Step 2: Lancer — échec attendu**

Run: `flutter test test/widget/tenant_punctuality_indicator_test.dart`
Expected: FAIL — `tenant_leases_provider.dart` / `tenant_punctuality_indicator.dart` inexistants.

- [ ] **Step 3: Créer `tenantLeasesProvider`**

`lib/features/tenants/application/tenant_leases_provider.dart` :

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tenant_repository.dart';

/// Baux d'un locataire (métadonnées brutes, dont `payment_day`), exposés en
/// provider pour les consommateurs Riverpod (ex. l'indicateur de ponctualité
/// agrégé). Thin wrapper sur [TenantRepository.listLeasesForTenant].
final tenantLeasesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      tenantId,
    ) {
      return ref.read(tenantRepositoryProvider).listLeasesForTenant(tenantId);
    });
```

- [ ] **Step 4: Créer `TenantPunctualityIndicator`**

`lib/features/tenants/presentation/widgets/tenant_punctuality_indicator.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../payments/application/lease_payments_provider.dart';
import '../../../payments/domain/payment_punctuality.dart';
import '../../../payments/presentation/widgets/payment_punctuality_indicator.dart';
import '../../application/tenant_leases_provider.dart';

/// Indicateur factuel de ponctualité de paiement agrégé sur l'ensemble des
/// baux d'UN locataire (son propre historique — jamais un comparatif entre
/// locataires). Somme la ponctualité par bail et réutilise la présentation de
/// [PaymentPunctualityView]. Donnée privée, jamais partagée.
class TenantPunctualityIndicator extends ConsumerWidget {
  const TenantPunctualityIndicator({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leases = ref.watch(tenantLeasesProvider(tenantId)).valueOrNull;
    if (leases == null) return const SizedBox.shrink();

    final parts = <PaymentPunctuality>[];
    for (final lease in leases) {
      final leaseId = lease['id'] as String?;
      final paymentDay = lease['payment_day'] as int?;
      if (leaseId == null || paymentDay == null) continue;
      final payments = ref.watch(leasePaymentsProvider(leaseId)).valueOrNull;
      // Un bail encore en chargement → on n'affiche pas de valeur partielle.
      if (payments == null) return const SizedBox.shrink();
      parts.add(computePaymentPunctuality(payments, paymentDay: paymentDay));
    }

    final k = combinePaymentPunctuality(parts);
    if (!k.hasPayments) return const SizedBox.shrink();
    return PaymentPunctualityView(k: k);
  }
}
```

- [ ] **Step 5: Insérer en tête de la fiche locataire**

Dans `lib/features/tenants/presentation/tenant_detail_page.dart`, dans `_TenantDetailContent.build`, insérer l'agrégat juste après `_InfoCard(tenant: tenant)` :

```dart
            _InfoCard(tenant: tenant),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TenantPunctualityIndicator(tenantId: tenant.id),
            ),
            const SizedBox(height: 24),

            // Section baux liés
            _LeasesSection(tenantId: tenant.id),
```

Ajouter l'import `import 'widgets/tenant_punctuality_indicator.dart';`.

- [ ] **Step 6: Lancer — vert + analyze**

Run: `flutter test test/widget/tenant_punctuality_indicator_test.dart && flutter analyze`
Expected: PASS, No issues found!

- [ ] **Step 7: Commit**

```bash
git add lib/features/tenants/application/tenant_leases_provider.dart lib/features/tenants/presentation/widgets/tenant_punctuality_indicator.dart lib/features/tenants/presentation/tenant_detail_page.dart test/widget/tenant_punctuality_indicator_test.dart
git commit -m "feat(tenants): indicateur de ponctualité agrégé en tête de fiche locataire

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Ponctualité par bail dans `TenantLeaseSummary`

Injecter l'indicateur #175 (`PaymentPunctualityIndicator`) sur chaque ligne de baux de la fiche locataire, quand `payment_day` est présent.

**Files:**
- Modify: `lib/features/tenants/presentation/widgets/tenant_lease_summary.dart`
- Test: `test/widget/tenant_lease_summary_test.dart`

**Interfaces:**
- Consumes: `PaymentPunctualityIndicator({required String leaseId, required int paymentDay})` (#175), maps de baux avec `payment_day` (Task 3), `leasePaymentsProvider`.

- [ ] **Step 1: Écrire le test**

Ajouter dans `test/widget/tenant_lease_summary_test.dart` (adapter les imports en tête du fichier si absents : `flutter_riverpod`, `lease_payments_provider`, `payment.dart`, `app_theme`, `app_localizations`, `locale_resolution`). Le fake `LeasePaymentsNotifier` suit le même pattern que `tenant_punctuality_indicator_test.dart` (Task 4) :

```dart
class _FakePayments extends LeasePaymentsNotifier {
  _FakePayments(this._payments);
  final List<Payment> _payments;
  @override
  Future<List<Payment>> build(String arg) async => _payments;
}

testWidgets('ligne de bail porte l\'indicateur de ponctualité si payment_day', (
  tester,
) async {
  final payments = [
    Payment(
      id: 'p1',
      leaseId: 'lz',
      landlordId: 'lord1',
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 31),
      paidAt: DateTime(2026, 1, 8), // échéance 5 + 5j = 10 → à l'heure
      rentAmountCents: 80000,
      chargesAmountCents: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        leasePaymentsProvider.overrideWith(() => _FakePayments(payments)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('fr'),
        supportedLocales: supportedLocales,
        home: const Scaffold(
          body: TenantLeaseSummary(
            leases: [
              {
                'id': 'lz',
                'status': 'active',
                'start_date': '2026-01-01T00:00:00.000Z',
                'end_date': null,
                'rent_amount_cents': 80000,
                'payment_day': 5,
              },
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('payment_punctuality_tap')), findsOneWidget);
});
```

Si le fichier construit ses baux via un helper partagé, y ajouter `'payment_day'`. Vérifier que le constructeur `Payment` ci-dessus correspond au modèle réel (`lib/features/payments/domain/payment.dart`) et ajuster les champs si nécessaire.

- [ ] **Step 2: Lancer — échec attendu**

Run: `flutter test test/widget/tenant_lease_summary_test.dart`
Expected: FAIL — aucun indicateur rendu sur la ligne.

- [ ] **Step 3: Injecter l'indicateur dans `_LeaseItem`**

Dans `tenant_lease_summary.dart` :
- Ajouter l'import `import '../../../payments/presentation/widgets/payment_punctuality_indicator.dart';`.
- Dans `_LeaseItem.build`, lire `final paymentDay = lease['payment_day'] as int?;`.
- Dans la `Column` interne (après le `Text` du loyer, avant/après le lien « voir le bail »), ajouter :

```dart
                    if (leaseId.isNotEmpty && paymentDay != null) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PaymentPunctualityIndicator(
                          leaseId: leaseId,
                          paymentDay: paymentDay,
                        ),
                      ),
                    ],
```

- [ ] **Step 4: Lancer — vert + analyze**

Run: `flutter test test/widget/tenant_lease_summary_test.dart && flutter analyze`
Expected: PASS, No issues found!

- [ ] **Step 5: Commit**

```bash
git add lib/features/tenants/presentation/widgets/tenant_lease_summary.dart test/widget/tenant_lease_summary_test.dart
git commit -m "feat(tenants): ponctualité par bail sur les lignes de la fiche locataire

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Vérification finale (après les 5 tâches)

- Run: `flutter analyze` → « No issues found! »
- Run: `flutter test` → suite complète verte.
- Contrôle : fiche locataire montre l'agrégat en tête (ligne/pill + tap → feuille) et la ponctualité par bail sur chaque ligne ; 0 paiement → rien ; jamais de comparatif inter-locataires.
- `docs/state/` : la fiche locataire ne change pas de modèle Firestore ; entrée `docs/state/CHANGELOG.md` à ajouter à la finition de branche (référence PR).
