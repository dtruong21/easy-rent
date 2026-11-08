# Fiche bail — indicateur de ponctualité de paiement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Afficher, en tête de la section « Paiements » de la fiche bail, un indicateur factuel de ponctualité (« X/Y à l'heure · N en retard »), responsive (ligne complète en large, pill compact <600 px, détail au tap).

**Architecture:** Un helper d'échéance public extrait de `lease_lateness.dart`, un helper pur `computePaymentPunctuality` dans le domaine paiements, et un `ConsumerWidget` responsive qui `ref.watch` le provider de paiements déjà chargé par la section (zéro nouvelle requête). Tout est factuel, privé, sans score subjectif.

**Tech Stack:** Flutter + Riverpod 2.6 (FamilyAsyncNotifier), freezed (existant), i18n `.arb` + `flutter gen-l10n`, breakpoints `core/ui/breakpoints.dart` (mobile < 600 px).

## Global Constraints

- **Zéro nouvelle requête Firestore** : le widget `ref.watch(leasePaymentsProvider(leaseId))` (déjà chargé par `PaymentListSection`) ; aucun accès Firestore direct.
- **« à l'heure »** = `!paidAt.isAfter(échéance + kDefaultLeaseGraceDays)` avec échéance = `leaseDueDate(paymentDay, periodStart.year, periodStart.month)` = `min(paymentDay, dernier jour du mois)`. `kDefaultLeaseGraceDays = 5` (déjà public dans `lease_lateness.dart`).
- **Pourcentage** affiché **seulement si `total >= 3`** ; sinon comptes bruts seuls.
- **Responsive** : `context.isMobile` (`< 600 px`, `core/ui/breakpoints.dart`) → pill compact ; sinon ligne complète. Détail au **tap** (bottom sheet) dans les deux cas.
- **Paiements soft-deleted** (`deletedAt != null`) **ignorés**.
- **Jetons uniquement** : `Theme.of(context).extension<AppColors>()!` (`.success` / `.warning` / `.neutral`, champ `.solid`, + `.surface` pour le fond du pill), `AppSpacing`. Aucune couleur en dur.
- **i18n** FR + EN, via `context.l10n` ; clés dans `app_fr.arb` **et** `app_en.arb` (descriptions `@key` sur le template `app_en.arb`), puis `flutter gen-l10n`. Générés gitignorés.
- **Privé / factuel** : aucun score/lettre/étoile ; jamais partagé/exporté ; aucune agrégation inter-locataires.
- Chaque tâche : `dart format` + `flutter analyze` clean sur les fichiers touchés, commit (chemins explicites, jamais `git add -A`), toute commande flutter/dart/git préfixée de `export PATH="/opt/homebrew/bin:$PATH"`.

---

### Task 1 : Fonction d'échéance publique `leaseDueDate`

**Files:**
- Modify: `lib/features/leases/domain/lease_lateness.dart` (rendre l'échéance publique, réutiliser dans `_dueDateFor`)
- Test: `test/unit/lease_due_date_test.dart`

**Interfaces:**
- Produces: `DateTime leaseDueDate({required int paymentDay, required int year, required int month})` — `min(paymentDay, dernierJourDuMois(year, month))` de ce mois.

- [ ] **Step 1 : Test qui échoue**

```dart
// test/unit/lease_due_date_test.dart
import 'package:easyrent/features/leases/domain/lease_lateness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('échéance = paymentDay quand le mois est assez long', () {
    expect(leaseDueDate(paymentDay: 5, year: 2026, month: 3), DateTime(2026, 3, 5));
  });
  test('clamp paymentDay 31 en février (28 j en 2026)', () {
    expect(leaseDueDate(paymentDay: 31, year: 2026, month: 2), DateTime(2026, 2, 28));
  });
  test('clamp paymentDay 31 en avril (30 j)', () {
    expect(leaseDueDate(paymentDay: 31, year: 2026, month: 4), DateTime(2026, 4, 30));
  });
}
```

- [ ] **Step 2 : Lancer → échoue**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/unit/lease_due_date_test.dart`
Expected: FAIL (`leaseDueDate` introuvable).

- [ ] **Step 3 : Extraire la fonction publique**

Dans `lib/features/leases/domain/lease_lateness.dart`, ajouter la fonction publique (à côté de `_dueDateFor`) et faire pointer `_dueDateFor` dessus :

```dart
/// Date d'échéance du mois [month]/[year] pour un jour d'échéance [paymentDay],
/// clampée au dernier jour du mois si celui-ci est plus court. Publique pour
/// être réutilisée (indicateur de ponctualité des paiements).
DateTime leaseDueDate({
  required int paymentDay,
  required int year,
  required int month,
}) {
  final lastDay = _lastDayOfMonth(year, month);
  final day = paymentDay > lastDay ? lastDay : paymentDay;
  return DateTime(year, month, day);
}
```

Puis remplacer le corps de `_dueDateFor` :

```dart
DateTime _dueDateFor(_YearMonth ym, int paymentDay) =>
    leaseDueDate(paymentDay: paymentDay, year: ym.year, month: ym.month);
```

- [ ] **Step 4 : Lancer → passe (nouveau + non-régression lateness)**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/unit/lease_due_date_test.dart $(rg -l "isLeaseLate|lease_lateness" test/ | tr '\n' ' ')`
Expected: PASS (le refactor ne change pas le comportement de `isLeaseLate`).

- [ ] **Step 5 : format + analyze + commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"
dart format lib/features/leases/domain/lease_lateness.dart test/unit/lease_due_date_test.dart
flutter analyze lib/features/leases/domain/lease_lateness.dart
git add lib/features/leases/domain/lease_lateness.dart test/unit/lease_due_date_test.dart
git commit -m "refactor(leases): expose leaseDueDate() pour réutilisation"
```

---

### Task 2 : Helper `computePaymentPunctuality`

**Files:**
- Create: `lib/features/payments/domain/payment_punctuality.dart`
- Test: `test/unit/payment_punctuality_test.dart`

**Interfaces:**
- Consumes: `leaseDueDate(...)` (Task 1), `kDefaultLeaseGraceDays` (public, `lease_lateness.dart`), `Payment` (`periodStart` DateTime, `paidAt` DateTime, `deletedAt` DateTime?).
- Produces:
  - `class PaymentPunctuality { final int total; final int onTime; int get late; bool get hasPayments; int? get onTimePercent; }`
  - `PaymentPunctuality computePaymentPunctuality(List<Payment> payments, {required int paymentDay, int graceDays = kDefaultLeaseGraceDays})`

- [ ] **Step 1 : Test qui échoue**

```dart
// test/unit/payment_punctuality_test.dart
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/payments/domain/payment_punctuality.dart';
import 'package:flutter_test/flutter_test.dart';

Payment _pay({
  required DateTime periodStart,
  required DateTime paidAt,
  DateTime? deletedAt,
}) => Payment(
  id: 'p-${paidAt.millisecondsSinceEpoch}',
  leaseId: 'l1',
  landlordId: 'lord1',
  periodStart: periodStart,
  periodEnd: DateTime(periodStart.year, periodStart.month + 1, 0),
  paidAt: paidAt,
  rentAmountCents: 80000,
  chargesAmountCents: 0,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2020, 1, 1),
  updatedAt: DateTime(2020, 1, 1),
  deletedAt: deletedAt,
);

void main() {
  // paymentDay = 5. Échéance mars 2026 = 5 mars ; deadline = 10 mars (grâce 5j).
  test('réglé le jour de la deadline (échéance + 5 j) → à l\'heure', () {
    final k = computePaymentPunctuality(
      [_pay(periodStart: DateTime(2026, 3, 1), paidAt: DateTime(2026, 3, 10))],
      paymentDay: 5,
    );
    expect(k.total, 1);
    expect(k.onTime, 1);
    expect(k.late, 0);
  });
  test('réglé à échéance + 6 j → en retard', () {
    final k = computePaymentPunctuality(
      [_pay(periodStart: DateTime(2026, 3, 1), paidAt: DateTime(2026, 3, 11))],
      paymentDay: 5,
    );
    expect(k.onTime, 0);
    expect(k.late, 1);
  });
  test('soft-deleted ignoré', () {
    final k = computePaymentPunctuality(
      [
        _pay(periodStart: DateTime(2026, 3, 1), paidAt: DateTime(2026, 3, 3)),
        _pay(periodStart: DateTime(2026, 4, 1), paidAt: DateTime(2026, 4, 3), deletedAt: DateTime(2026, 5, 1)),
      ],
      paymentDay: 5,
    );
    expect(k.total, 1);
  });
  test('< 3 paiements → onTimePercent null ; >= 3 → arrondi', () {
    final two = computePaymentPunctuality(
      [
        _pay(periodStart: DateTime(2026, 1, 1), paidAt: DateTime(2026, 1, 3)),
        _pay(periodStart: DateTime(2026, 2, 1), paidAt: DateTime(2026, 2, 3)),
      ],
      paymentDay: 5,
    );
    expect(two.onTimePercent, isNull);
    final three = computePaymentPunctuality(
      [
        _pay(periodStart: DateTime(2026, 1, 1), paidAt: DateTime(2026, 1, 3)),
        _pay(periodStart: DateTime(2026, 2, 1), paidAt: DateTime(2026, 2, 3)),
        _pay(periodStart: DateTime(2026, 3, 1), paidAt: DateTime(2026, 3, 30)),
      ],
      paymentDay: 5,
    );
    expect(three.onTimePercent, 67); // 2/3 = 66.7 → 67
  });
  test('aucun paiement → hasPayments false', () {
    expect(computePaymentPunctuality([], paymentDay: 5).hasPayments, isFalse);
  });
}
```

> NOTE : vérifier la valeur exacte de `PaymentMethod` (fichier `payment_method.dart`) et remplacer `PaymentMethod.virement` par une valeur réelle si le nom diffère. Ajouter tout champ `required` que le compilateur signale sur `Payment`.

- [ ] **Step 2 : Lancer → échoue**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/unit/payment_punctuality_test.dart`
Expected: FAIL (helper/modèle introuvables).

- [ ] **Step 3 : Implémenter**

```dart
// lib/features/payments/domain/payment_punctuality.dart
import '../../leases/domain/lease_lateness.dart';
import 'payment.dart';

/// Ponctualité factuelle des paiements enregistrés d'un bail.
///
/// Purement dérivé des enregistrements du bailleur (paidAt vs échéance + grâce)
/// — aucun jugement, aucun score subjectif, jamais partagé.
class PaymentPunctuality {
  const PaymentPunctuality({required this.total, required this.onTime});

  final int total;
  final int onTime;

  int get late => total - onTime;
  bool get hasPayments => total > 0;

  /// Taux à l'heure entier — `null` sous 3 paiements (évite un % trompeur).
  int? get onTimePercent =>
      total >= 3 ? ((onTime / total) * 100).round() : null;
}

/// Calcule la ponctualité sur [payments] (soft-deleted ignorés).
/// « à l'heure » = `paidAt` au plus tard `échéance + graceDays`.
PaymentPunctuality computePaymentPunctuality(
  List<Payment> payments, {
  required int paymentDay,
  int graceDays = kDefaultLeaseGraceDays,
}) {
  var total = 0;
  var onTime = 0;
  for (final p in payments) {
    if (p.deletedAt != null) continue;
    total++;
    final due = leaseDueDate(
      paymentDay: paymentDay,
      year: p.periodStart.year,
      month: p.periodStart.month,
    );
    if (!p.paidAt.isAfter(due.add(Duration(days: graceDays)))) onTime++;
  }
  return PaymentPunctuality(total: total, onTime: onTime);
}
```

- [ ] **Step 4 : Lancer → passe**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/unit/payment_punctuality_test.dart`
Expected: PASS.

- [ ] **Step 5 : format + analyze + commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"
dart format lib/features/payments/domain/payment_punctuality.dart test/unit/payment_punctuality_test.dart
flutter analyze lib/features/payments/domain/payment_punctuality.dart
git add lib/features/payments/domain/payment_punctuality.dart test/unit/payment_punctuality_test.dart
git commit -m "feat(payments): helper de ponctualité de paiement (factuel)"
```

---

### Task 3 : Clés i18n

**Files:**
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`

**Interfaces:**
- Produces : `paymentsPunctualityOnTime(int onTime, int total)`, `paymentsPunctualityLate(int count)`, `paymentsPunctualityLateShort(int count)`, `paymentsPunctualityEmpty`, `paymentsPunctualitySheetTitle`, `paymentsPunctualityMethod`, `paymentsPunctualityPrivacy`, `paymentsPunctualityOnTimeLabel`, `paymentsPunctualityLateLabel`.

- [ ] **Step 1 : Clés FR** (avant l'accolade finale de `app_fr.arb`, virgule sur la clé précédente) :

```json
  "paymentsPunctualityOnTime": "{onTime}/{total} à l'heure",
  "@paymentsPunctualityOnTime": { "placeholders": { "onTime": { "type": "int" }, "total": { "type": "int" } } },
  "paymentsPunctualityLate": "{count} en retard",
  "@paymentsPunctualityLate": { "placeholders": { "count": { "type": "int" } } },
  "paymentsPunctualityLateShort": "{count} retard",
  "@paymentsPunctualityLateShort": { "placeholders": { "count": { "type": "int" } } },
  "paymentsPunctualityEmpty": "Aucun paiement enregistré",
  "paymentsPunctualitySheetTitle": "Ponctualité des paiements",
  "paymentsPunctualityMethod": "À l'heure = réglé sous 5 jours après l'échéance.",
  "paymentsPunctualityPrivacy": "Donnée privée, tirée de vos enregistrements. Jamais partagée.",
  "paymentsPunctualityOnTimeLabel": "À l'heure",
  "paymentsPunctualityLateLabel": "En retard"
```

- [ ] **Step 2 : Clés EN** (mêmes noms/placeholders, **avec `@key.description` sur chaque**) dans `app_en.arb` :

```json
  "paymentsPunctualityOnTime": "{onTime}/{total} on time",
  "@paymentsPunctualityOnTime": { "description": "Payments: on-time/total count", "placeholders": { "onTime": { "type": "int" }, "total": { "type": "int" } } },
  "paymentsPunctualityLate": "{count} late",
  "@paymentsPunctualityLate": { "description": "Payments: late count (full)", "placeholders": { "count": { "type": "int" } } },
  "paymentsPunctualityLateShort": "{count} late",
  "@paymentsPunctualityLateShort": { "description": "Payments: late count (compact pill)", "placeholders": { "count": { "type": "int" } } },
  "paymentsPunctualityEmpty": "No payment recorded",
  "@paymentsPunctualityEmpty": { "description": "Payments: punctuality empty state" },
  "paymentsPunctualitySheetTitle": "Payment punctuality",
  "@paymentsPunctualitySheetTitle": { "description": "Payments: punctuality detail sheet title" },
  "paymentsPunctualityMethod": "On time = paid within 5 days of the due date.",
  "@paymentsPunctualityMethod": { "description": "Payments: punctuality method note" },
  "paymentsPunctualityPrivacy": "Private, from your records. Never shared.",
  "@paymentsPunctualityPrivacy": { "description": "Payments: punctuality privacy note" },
  "paymentsPunctualityOnTimeLabel": "On time",
  "@paymentsPunctualityOnTimeLabel": { "description": "Payments: on-time tile label" },
  "paymentsPunctualityLateLabel": "Late",
  "@paymentsPunctualityLateLabel": { "description": "Payments: late tile label" }
```

- [ ] **Step 3 : Régénérer + vérifier**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter gen-l10n && flutter analyze lib/l10n/app_localizations.dart && flutter test test/l10n/arb_parity_test.dart`
Expected: OK, parité + descriptions vertes.

- [ ] **Step 4 : Commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"
git add lib/l10n/app_fr.arb lib/l10n/app_en.arb
git commit -m "i18n(payments): clés de l'indicateur de ponctualité"
```

---

### Task 4 : Widget `PaymentPunctualityIndicator` + intégration

**Files:**
- Create: `lib/features/payments/presentation/widgets/payment_punctuality_indicator.dart`
- Modify: `lib/features/payments/presentation/widgets/payment_list_section.dart` (en-tête de la section)
- Test: `test/widget/payment_punctuality_indicator_test.dart`

**Interfaces:**
- Consumes: `computePaymentPunctuality` + `PaymentPunctuality` (Task 2), clés i18n (Task 3), `leasePaymentsProvider` (`FamilyAsyncNotifier<List<Payment>, String>`), `context.isMobile` (`core/ui/breakpoints.dart`), `AppColors`.
- Produces: `class PaymentPunctualityIndicator extends ConsumerWidget` — `const PaymentPunctualityIndicator({super.key, required this.leaseId, required this.paymentDay})`.

**Comportement** : `ref.watch(leasePaymentsProvider(leaseId)).valueOrNull` ; si `null` → `SizedBox.shrink()` (chargement) ; sinon `computePaymentPunctuality(payments, paymentDay: paymentDay)`. Si `!hasPayments` → texte neutre `paymentsPunctualityEmpty`. Sinon : `context.isMobile` → pill compact (Key `payment_punctuality_pill`), sinon ligne complète (Key `payment_punctuality_line`) ; les deux dans un `InkWell`/`GestureDetector` (Key `payment_punctuality_tap`) ouvrant `showModalBottomSheet` de détail (Key `payment_punctuality_sheet`).

- [ ] **Step 1 : Test qui échoue**

```dart
// test/widget/payment_punctuality_indicator_test.dart
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/payments/application/lease_payments_provider.dart';
import 'package:easyrent/features/payments/domain/payment.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/payments/presentation/widgets/payment_punctuality_indicator.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePayments extends LeasePaymentsNotifier {
  _FakePayments(this._items);
  final List<Payment> _items;
  @override
  Future<List<Payment>> build(String arg) async => _items;
}

Payment _pay(DateTime periodStart, DateTime paidAt) => Payment(
  id: 'p-${paidAt.millisecondsSinceEpoch}',
  leaseId: 'l1',
  landlordId: 'lord1',
  periodStart: periodStart,
  periodEnd: DateTime(periodStart.year, periodStart.month + 1, 0),
  paidAt: paidAt,
  rentAmountCents: 80000,
  chargesAmountCents: 0,
  paymentMethod: PaymentMethod.virement,
  createdAt: DateTime(2020, 1, 1),
  updatedAt: DateTime(2020, 1, 1),
);

Widget _wrap(List<Payment> payments, {required double width}) => ProviderScope(
  overrides: [leasePaymentsProvider.overrideWith(() => _FakePayments(payments))],
  child: MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: const Scaffold(
        body: PaymentPunctualityIndicator(leaseId: 'l1', paymentDay: 5),
      ),
    ),
  ),
);

void main() {
  final onTime = _pay(DateTime(2026, 3, 1), DateTime(2026, 3, 3));
  final late = _pay(DateTime(2026, 4, 1), DateTime(2026, 4, 30));

  testWidgets('large → ligne complète', (tester) async {
    await tester.pumpWidget(_wrap([onTime, late], width: 1000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_line')), findsOneWidget);
    expect(find.byKey(const Key('payment_punctuality_pill')), findsNothing);
  });

  testWidgets('mobile → pill compact', (tester) async {
    await tester.pumpWidget(_wrap([onTime, late], width: 360));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_pill')), findsOneWidget);
  });

  testWidgets('tap → feuille de détail', (tester) async {
    await tester.pumpWidget(_wrap([onTime, late], width: 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payment_punctuality_tap')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_sheet')), findsOneWidget);
  });

  testWidgets('aucun paiement → texte neutre, pas de pill/ligne', (tester) async {
    await tester.pumpWidget(_wrap([], width: 360));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment_punctuality_pill')), findsNothing);
    expect(find.byKey(const Key('payment_punctuality_line')), findsNothing);
  });
}
```

> NOTE : override d'un `FamilyAsyncNotifierProvider` — `leasePaymentsProvider.overrideWith(() => _FakePayments(...))` remplace toutes les clés ; le fake surcharge `build(String arg)`. Vérifier la signature réelle de `LeasePaymentsNotifier.build` dans `lease_payments_provider.dart` et l'aligner. Remplacer `PaymentMethod.virement` par la valeur réelle si besoin.

- [ ] **Step 2 : Lancer → échoue**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/widget/payment_punctuality_indicator_test.dart`
Expected: FAIL (widget introuvable).

- [ ] **Step 3 : Implémenter le widget**

```dart
// lib/features/payments/presentation/widgets/payment_punctuality_indicator.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../application/lease_payments_provider.dart';
import '../../domain/payment_punctuality.dart';

/// Indicateur factuel de ponctualité de paiement, en tête de la section
/// Paiements d'un bail. Responsive : ligne complète en large, pill compact
/// (< 600 px), détail au tap. Donnée privée, jamais partagée.
class PaymentPunctualityIndicator extends ConsumerWidget {
  const PaymentPunctualityIndicator({
    super.key,
    required this.leaseId,
    required this.paymentDay,
  });

  final String leaseId;
  final int paymentDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final l10n = context.l10n;
    final payments = ref.watch(leasePaymentsProvider(leaseId)).valueOrNull;
    if (payments == null) return const SizedBox.shrink();

    final k = computePaymentPunctuality(payments, paymentDay: paymentDay);
    if (!k.hasPayments) {
      return Text(
        l10n.paymentsPunctualityEmpty,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.neutral.solid),
      );
    }

    final tone = k.late > 0 ? colors.warning : colors.success;

    Widget content;
    if (context.isMobile) {
      final label = k.late > 0
          ? '${k.onTime}/${k.total} · ${l10n.paymentsPunctualityLateShort(k.late)}'
          : '${k.onTime}/${k.total}';
      content = Container(
        key: const Key('payment_punctuality_pill'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: tone.surface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              k.late > 0 ? Icons.schedule : Icons.check_circle_outline,
              size: 14,
              color: tone.onSurface,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: tone.onSurface),
            ),
          ],
        ),
      );
    } else {
      final parts = <String>[
        l10n.paymentsPunctualityOnTime(k.onTime, k.total),
        if (k.late > 0) l10n.paymentsPunctualityLate(k.late),
        if (k.onTimePercent != null) '${k.onTimePercent} %',
      ];
      content = Row(
        key: const Key('payment_punctuality_line'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            k.late > 0 ? Icons.schedule : Icons.check_circle_outline,
            size: 16,
            color: tone.solid,
          ),
          const SizedBox(width: 6),
          Text(
            parts.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return InkWell(
      key: const Key('payment_punctuality_tap'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showDetail(context, k),
      child: content,
    );
  }

  void _showDetail(BuildContext context, PaymentPunctuality k) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colors = theme.extension<AppColors>()!;
        final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
        return Padding(
          key: const Key('payment_punctuality_sheet'),
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.paymentsPunctualitySheetTitle,
                style: theme.textTheme.titleMedium,
              ),
              SizedBox(height: spacing.xs),
              Text(
                l10n.paymentsPunctualityMethod,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: spacing.md),
              Row(
                children: [
                  Expanded(
                    child: _DetailTile(
                      label: l10n.paymentsPunctualityOnTimeLabel,
                      value: '${k.onTime}/${k.total}',
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: _DetailTile(
                      label: l10n.paymentsPunctualityLateLabel,
                      value: k.late.toString(),
                      color: colors.warning.solid,
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              Text(
                l10n.paymentsPunctualityPrivacy,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
```

> NOTE : `StatusColorSet` expose `surface`, `onSurface`, `solid`, `onSolid` (cf. `lib/core/ui/theme/app_colors.dart`). Si `surfaceContainerHigh` n'existe pas sur le `ColorScheme`, utiliser `surfaceContainerHighest`.

- [ ] **Step 4 : Lancer le test ciblé → passe**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter test test/widget/payment_punctuality_indicator_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5 : Intégrer dans l'en-tête de la section Paiements**

Dans `lib/features/payments/presentation/widgets/payment_list_section.dart`, dans le `Row` d'en-tête, insérer l'indicateur **après le titre** et avant `const Spacer()`. Le bail est disponible dans ce scope (`_PaymentListContent` porte `lease`) — utiliser `lease.paymentDay`. Ajouter l'import `import 'payment_punctuality_indicator.dart';`. Insérer :

```dart
                Text(
                  context.l10n.paymentsSectionTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PaymentPunctualityIndicator(
                      leaseId: leaseId,
                      paymentDay: lease.paymentDay,
                    ),
                  ),
                ),
                const Spacer(),
```

> `Flexible` évite un overflow si le pill + titre + bouton dépassent en étroit. Vérifier au rendu (mobile) qu'il n'y a pas de RenderFlex overflow ; si nécessaire, réduire le libellé du bouton ajouter n'est PAS permis (hors périmètre) — préférer envelopper l'indicateur dans `Flexible` (déjà fait) qui tronquera plutôt que déborder.

- [ ] **Step 6 : Suite complète + analyze**

Run: `export PATH="/opt/homebrew/bin:$PATH" && flutter analyze && flutter test`
Expected: `No issues found` + tous les tests verts (dont `payment_list_section_test.dart` — vérifier qu'il fournit `leasePaymentsProvider` ou tolère son absence ; l'indicateur rend `SizedBox.shrink` tant que le provider n'a pas résolu, donc pas de casse).

- [ ] **Step 7 : format + commit**

```bash
export PATH="/opt/homebrew/bin:$PATH"
dart format lib/features/payments/presentation/widgets/payment_punctuality_indicator.dart lib/features/payments/presentation/widgets/payment_list_section.dart test/widget/payment_punctuality_indicator_test.dart
git add lib/features/payments/presentation/widgets/payment_punctuality_indicator.dart lib/features/payments/presentation/widgets/payment_list_section.dart test/widget/payment_punctuality_indicator_test.dart
git commit -m "feat(payments): indicateur de ponctualité responsive dans la section Paiements"
```

---

## Notes d'exécution transverses

- **Vérifier les `required` de `Payment`** (freezed) au premier compile : le fixture doit fournir `id`, `leaseId`, `landlordId`, `periodStart`, `periodEnd`, `paidAt`, `rentAmountCents`, `chargesAmountCents`, `paymentMethod`, `createdAt`, `updatedAt` (+ `deletedAt?`). Valeur `PaymentMethod` réelle à confirmer dans `payment_method.dart`.
- **`LeasePaymentsNotifier.build`** a la signature `Future<List<Payment>> build(String arg)` (FamilyAsyncNotifier) — le fake doit la surcharger à l'identique.
- **Ne pas** modifier `KpiCard`, le panneau dashboard, ni le calcul de `lease_lateness` (au-delà du refactor `_dueDateFor`).
- **docs/state/** : après merge, `state-keeper` sur `routes/payments-receipts.md` (indicateur ajouté) — hors périmètre code.
