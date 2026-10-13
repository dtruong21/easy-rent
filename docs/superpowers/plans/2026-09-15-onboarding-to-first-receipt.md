# Onboarding jusqu'à la 1re quittance — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformer la checklist d'onboarding statique (3 étapes, disparaît au 1er bien) en checklist progressive à état qui guide le bailleur jusqu'à sa 1re quittance (5 étapes cochées depuis les données).

**Architecture:** 100 % client, lecture seule. Un modèle `OnboardingProgress` dérivé de 5 requêtes `limit(1)`, un provider dashboard qui affiche la checklist tant qu'aucune quittance n'existe (et non « passée »), un widget piloté par la progression, un dismiss local en `SharedPreferences`. Aucun backend.

**Tech Stack:** Flutter/Dart, Riverpod, freezed, SharedPreferences, cloud_firestore.

## Global Constraints

- **Aucune écriture Firestore, aucun nouveau champ/collection, aucun backend.** Lecture seule + une préférence locale.
- **Accès Firestore via `firestoreProvider`** (jamais `FirebaseFirestore.instance` hors main.dart).
- **Fin de l'onboarding = 1re quittance** (`hasReceipt`). 5 étapes séparées. Checklist = élément principal jusqu'à complétion.
- **Étapes 4-5 lease-scoped** : routes `/leases/<firstLeaseId>/payments/new` et `/leases/<firstLeaseId>/receipts` ; désactivées tant qu'aucun bail (`firstLeaseId == null`).
- **i18n** : toute chaîne visible passe par `.arb` FR/EN, `@description` sur le template EN, parité `test/l10n/arb_parity_test.dart`, `flutter gen-l10n`.
- **Build vert à chaque tâche** : `flutter analyze` clean + tests. Formatage : `dart format .` avant chaque commit (la CI lance `dart format --set-exit-if-changed .` sur tout le repo).
- Freezed : après toute modif de classe freezed, lancer `dart run build_runner build --delete-conflicting-outputs`.

---

### Task 1: Modèle `OnboardingProgress`

**Files:**
- Create: `lib/features/dashboard/domain/onboarding_progress.dart`
- Test: `test/unit/onboarding_progress_test.dart`

**Interfaces:**
- Produces: `OnboardingProgress({bool hasProperty, hasTenant, hasLease, hasPayment, hasReceipt, String? firstLeaseId})` avec getters `bool get isComplete` (= `hasReceipt`) et `int get completedCount` (0-5).

- [ ] **Step 1: Écrire le test (échoue)**

`test/unit/onboarding_progress_test.dart` :

```dart
import 'package:easyrent/features/dashboard/domain/onboarding_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnboardingProgress', () {
    test('isComplete suit hasReceipt', () {
      const notDone = OnboardingProgress(
        hasProperty: true,
        hasTenant: true,
        hasLease: true,
        hasPayment: true,
        hasReceipt: false,
        firstLeaseId: 'l1',
      );
      expect(notDone.isComplete, isFalse);
      expect(notDone.copyWith(hasReceipt: true).isComplete, isTrue);
    });

    test('completedCount compte les étapes vraies', () {
      const p = OnboardingProgress(
        hasProperty: true,
        hasTenant: true,
        hasLease: false,
        hasPayment: false,
        hasReceipt: false,
        firstLeaseId: null,
      );
      expect(p.completedCount, 2);
    });

    test('completedCount = 5 quand tout est fait', () {
      const p = OnboardingProgress(
        hasProperty: true,
        hasTenant: true,
        hasLease: true,
        hasPayment: true,
        hasReceipt: true,
        firstLeaseId: 'l1',
      );
      expect(p.completedCount, 5);
    });
  });
}
```

- [ ] **Step 2: Lancer — échoue** — `flutter test test/unit/onboarding_progress_test.dart` → FAIL (classe absente).

- [ ] **Step 3: Écrire le modèle**

`lib/features/dashboard/domain/onboarding_progress.dart` :

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'onboarding_progress.freezed.dart';

/// Progression d'onboarding d'un bailleur, dérivée des collections existantes
/// (aucune écriture, aucun champ Firestore dédié).
///
/// [firstLeaseId] : id d'un bail du bailleur (pour router les étapes 4-5,
/// lease-scoped) ; `null` tant qu'aucun bail n'existe.
///
/// [isComplete] : l'onboarding s'achève à la 1re quittance générée
/// (`hasReceipt`) — le moment de valeur (quittance loi 6 juillet 1989).
@freezed
class OnboardingProgress with _$OnboardingProgress {
  const OnboardingProgress._();

  const factory OnboardingProgress({
    required bool hasProperty,
    required bool hasTenant,
    required bool hasLease,
    required bool hasPayment,
    required bool hasReceipt,
    required String? firstLeaseId,
  }) = _OnboardingProgress;

  bool get isComplete => hasReceipt;

  int get completedCount => [
    hasProperty,
    hasTenant,
    hasLease,
    hasPayment,
    hasReceipt,
  ].where((e) => e).length;
}
```

- [ ] **Step 4: Générer freezed** — `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 5: Lancer — passe** — `flutter test test/unit/onboarding_progress_test.dart` → PASS

- [ ] **Step 6: Commit**

```bash
dart format lib/features/dashboard/domain/onboarding_progress.dart test/unit/onboarding_progress_test.dart
git add lib/features/dashboard/domain/onboarding_progress.dart lib/features/dashboard/domain/onboarding_progress.freezed.dart test/unit/onboarding_progress_test.dart
git commit -m "feat(dashboard): modèle OnboardingProgress (5 étapes dérivées)"
```

---

### Task 2: `DashboardRepository.fetchOnboardingProgress()`

Ajoute la lecture de progression **à côté** de `isLandlordOnboarding()` (retiré en Task 4). Additif — le build reste vert.

**Files:**
- Modify: `lib/features/dashboard/data/dashboard_repository.dart` (interface + impl)
- Test: `test/unit/dashboard_onboarding_progress_test.dart`

**Interfaces:**
- Consumes: `OnboardingProgress` (Task 1).
- Produces: `Future<OnboardingProgress> fetchOnboardingProgress()` sur `DashboardRepository`.

- [ ] **Step 1: Écrire le test (échoue)**

`test/unit/dashboard_onboarding_progress_test.dart` — s'appuyer sur `fake_cloud_firestore` (patron `dashboard_repository_firestore_test.dart`). Construire `FirestoreDashboardRepository(fakeFirestore, fakeAuth)` avec un uid connu.

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uid = 'landlord-1';
  late FakeFirebaseFirestore db;
  late FirestoreDashboardRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreDashboardRepository(db, MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid),
    ));
  });

  Future<void> seed(String col, Map<String, dynamic> data) =>
      db.collection(col).add({'landlordId': uid, 'deletedAt': null, ...data});

  test('compte vide → tout false, firstLeaseId null', () async {
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasProperty, isFalse);
    expect(p.hasReceipt, isFalse);
    expect(p.firstLeaseId, isNull);
    expect(p.isComplete, isFalse);
  });

  test('un bien seul → hasProperty true, reste false', () async {
    await seed('properties', {'name': 'B1'});
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasProperty, isTrue);
    expect(p.hasTenant, isFalse);
    expect(p.hasLease, isFalse);
  });

  test('un bail → firstLeaseId renseigné', () async {
    final ref = await db.collection('leases').add({
      'landlordId': uid,
      'deletedAt': null,
    });
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasLease, isTrue);
    expect(p.firstLeaseId, ref.id);
  });

  test('une quittance → isComplete true', () async {
    await db.collection('receipts').add({'landlordId': uid});
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasReceipt, isTrue);
    expect(p.isComplete, isTrue);
  });

  test('ignore les docs soft-deleted', () async {
    await db.collection('properties').add({
      'landlordId': uid,
      'deletedAt': Timestamp.now(),
    });
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasProperty, isFalse);
  });
}
```

> Si les mocks `firebase_auth_mocks` / `fake_cloud_firestore` ne sont pas déjà dans `pubspec` dev, se caler exactement sur ce qu'utilise `dashboard_repository_firestore_test.dart` (mêmes imports/mocks) — ne pas introduire de nouvelle dépendance.

- [ ] **Step 2: Lancer — échoue** (`flutter test test/unit/dashboard_onboarding_progress_test.dart`) — méthode absente.

- [ ] **Step 3: Ajouter la méthode**

Dans l'interface `DashboardRepository`, ajouter :

```dart
  /// Progression d'onboarding dérivée (5 signaux + id d'un bail). Lecture seule.
  Future<OnboardingProgress> fetchOnboardingProgress();
```

Import en tête : `import '../domain/onboarding_progress.dart';`

Dans `FirestoreDashboardRepository`, implémenter (patron des 3 requêtes parallèles de `isLandlordOnboarding`, étendu à 5) :

```dart
  @override
  Future<OnboardingProgress> fetchOnboardingProgress() async {
    final uid = _uid;

    Query<Map<String, dynamic>> owned(String col) => _firestore
        .collection(col)
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .limit(1);

    final results = await Future.wait([
      owned('properties').get(),
      owned('tenants').get(),
      owned('leases').get(),
      owned('payments').get(),
      // receipts : collection immuable read-only (pas de deletedAt) ; un
      // receipt compte même s'il est ensuite isVoided — l'aha, c'est de
      // l'avoir généré.
      _firestore
          .collection('receipts')
          .where('landlordId', isEqualTo: uid)
          .limit(1)
          .get(),
    ]);

    final leaseDocs = results[2].docs;
    return OnboardingProgress(
      hasProperty: results[0].docs.isNotEmpty,
      hasTenant: results[1].docs.isNotEmpty,
      hasLease: leaseDocs.isNotEmpty,
      hasPayment: results[3].docs.isNotEmpty,
      hasReceipt: results[4].docs.isNotEmpty,
      firstLeaseId: leaseDocs.isNotEmpty ? leaseDocs.first.id : null,
    );
  }
```

- [ ] **Step 4: Lancer — passe** (`flutter test test/unit/dashboard_onboarding_progress_test.dart`).

- [ ] **Step 5: analyze** — `flutter analyze lib/features/dashboard/data/dashboard_repository.dart` → clean.

- [ ] **Step 6: Commit**

```bash
dart format lib/features/dashboard/data/dashboard_repository.dart test/unit/dashboard_onboarding_progress_test.dart
git add lib/features/dashboard/data/dashboard_repository.dart test/unit/dashboard_onboarding_progress_test.dart
git commit -m "feat(dashboard): fetchOnboardingProgress (5 signaux dérivés)"
```

---

### Task 3: Dismiss local (`SharedPreferences`)

**Files:**
- Create: `lib/features/dashboard/application/onboarding_dismissed_provider.dart`
- Test: `test/unit/onboarding_dismissed_provider_test.dart`

**Interfaces:**
- Produces: `onboardingDismissedProvider` (`StateNotifierProvider<OnboardingDismissedNotifier, bool>`), méthode `dismiss()`. Storage `OnboardingDismissedStorage` (clé `onboarding_dismissed`).

- [ ] **Step 1: Écrire le test (échoue)**

`test/unit/onboarding_dismissed_provider_test.dart` :

```dart
import 'package:easyrent/features/dashboard/application/onboarding_dismissed_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('défaut false ; dismiss() → true et persiste', () async {
    final storage = OnboardingDismissedStorage();
    expect(await storage.read(), isFalse);
    await storage.write(true);
    expect(await storage.read(), isTrue);
  });
}
```

- [ ] **Step 2: Lancer — échoue.**

- [ ] **Step 3: Écrire le provider** (patron `chart_period_provider.dart`)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste le fait que le bailleur a « passé » la checklist d'onboarding
/// (préférence LOCALE au navigateur/appareil — pas de synchro serveur).
class OnboardingDismissedStorage {
  static const _key = 'onboarding_dismissed';

  Future<bool> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> write(bool dismissed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, dismissed);
  }
}

final onboardingDismissedStorageProvider = Provider<OnboardingDismissedStorage>(
  (ref) => OnboardingDismissedStorage(),
);

/// `true` si le bailleur a masqué la checklist. Démarre `false`, charge la
/// valeur stockée (même compromis que `ChartPeriodNotifier`).
class OnboardingDismissedNotifier extends StateNotifier<bool> {
  OnboardingDismissedNotifier(this._storage) : super(false) {
    _load();
  }

  final OnboardingDismissedStorage _storage;

  Future<void> _load() async {
    final stored = await _storage.read();
    if (stored && mounted) state = true;
  }

  Future<void> dismiss() async {
    state = true;
    await _storage.write(true);
  }
}

final onboardingDismissedProvider =
    StateNotifierProvider<OnboardingDismissedNotifier, bool>(
      (ref) => OnboardingDismissedNotifier(
        ref.read(onboardingDismissedStorageProvider),
      ),
    );
```

- [ ] **Step 4: Lancer — passe.**

- [ ] **Step 5: Commit**

```bash
dart format lib/features/dashboard/application/onboarding_dismissed_provider.dart test/unit/onboarding_dismissed_provider_test.dart
git add lib/features/dashboard/application/onboarding_dismissed_provider.dart test/unit/onboarding_dismissed_provider_test.dart
git commit -m "feat(dashboard): dismiss local de l'onboarding (SharedPreferences)"
```

---

### Task 4: Câblage snapshot + provider

Adapte `DashboardSnapshot` pour porter la progression, câble le provider (`showOnboarding = !isComplete && !dismissed`), retire `isLandlordOnboarding`.

**Files:**
- Modify: `lib/features/dashboard/domain/dashboard_snapshot.dart`
- Modify: `lib/features/dashboard/application/dashboard_provider.dart`
- Modify: `lib/features/dashboard/data/dashboard_repository.dart` (retirer `isLandlordOnboarding` de l'interface + impl)
- Test: `test/unit/dashboard_snapshot_test.dart` (étendre)

**Interfaces:**
- Consumes: `OnboardingProgress`, `onboardingDismissedProvider`, `fetchOnboardingProgress`.
- Produces: `DashboardSnapshot.onboarding` (`OnboardingProgress?`, non-null en mode onboarding) ; `isOnboarding` dérivé de sa présence.

- [ ] **Step 1: Étendre `DashboardSnapshot`**

Ajouter un champ `OnboardingProgress? onboarding` au factory freezed, et remplacer le `bool isOnboarding` requis par un getter dérivé :

```dart
// import '../domain/onboarding_progress.dart'; en tête
  const DashboardSnapshot._();

  const factory DashboardSnapshot({
    required LoyersMoisKpi loyers,
    required RetardsKpi retards,
    required DocsPendingKpi docs,
    required List<ActivityItem> activity,
    OnboardingProgress? onboarding,
  }) = _DashboardSnapshot;

  bool get isOnboarding => onboarding != null;

  factory DashboardSnapshot.onboarding(OnboardingProgress progress) =>
      DashboardSnapshot(
        loyers: const LoyersMoisKpi(encaissedCents: 0, dueCents: 0),
        retards: const RetardsKpi(count: 0),
        docs: const DocsPendingKpi(count: 0),
        activity: const [],
        onboarding: progress,
      );
```

> Retirer l'ancienne factory `DashboardSnapshot.empty({required bool isOnboarding})` et le champ `isOnboarding` requis. Ajouter `const DashboardSnapshot._();` pour autoriser le getter. Regénérer freezed.

- [ ] **Step 2: Câbler le provider**

Dans `dashboard_provider.dart` `build()` :

```dart
    final repo = ref.watch(dashboardRepositoryProvider);
    final progress = await repo.fetchOnboardingProgress();
    final dismissed = ref.watch(onboardingDismissedProvider);

    if (!progress.isComplete && !dismissed) {
      _log.info('Landlord en onboarding — skip KPI queries');
      return DashboardSnapshot.onboarding(progress);
    }

    // fan-in KPI inchangé …
    return DashboardSnapshot(
      loyers: loyers,
      retards: retards,
      docs: docs,
      activity: activity,
      // onboarding: null (défaut)
    );
```

Import : `import 'onboarding_dismissed_provider.dart';`. Retirer l'appel `isLandlordOnboarding()`.

- [ ] **Step 3: Retirer `isLandlordOnboarding`** de l'interface et de l'impl du repository (plus aucun appelant). Vérifier via `grep -rn isLandlordOnboarding lib test` → aucune référence restante (mettre à jour les tests qui la ciblaient, le cas échéant).

- [ ] **Step 4: Générer freezed** — `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 5: Étendre `dashboard_snapshot_test.dart`**

Ajouter :

```dart
  test('isOnboarding dérive de la présence de onboarding', () {
    const progress = OnboardingProgress(
      hasProperty: false, hasTenant: false, hasLease: false,
      hasPayment: false, hasReceipt: false, firstLeaseId: null,
    );
    expect(DashboardSnapshot.onboarding(progress).isOnboarding, isTrue);
    expect(
      DashboardSnapshot(
        loyers: const LoyersMoisKpi(encaissedCents: 0, dueCents: 0),
        retards: const RetardsKpi(count: 0),
        docs: const DocsPendingKpi(count: 0),
        activity: const [],
      ).isOnboarding,
      isFalse,
    );
  });
```

(adapter les imports/asserts existants du fichier au nouveau modèle).

- [ ] **Step 6: analyze + tests dashboard**

Run: `flutter analyze lib/features/dashboard && flutter test test/unit/dashboard_snapshot_test.dart test/unit/dashboard_onboarding_progress_test.dart`
Expected: clean + PASS. (Corriger toute référence cassée à l'ancien `isOnboarding`/`empty`.)

- [ ] **Step 7: Commit**

```bash
dart format lib/features/dashboard test/unit/dashboard_snapshot_test.dart
git add lib/features/dashboard/domain/dashboard_snapshot.dart lib/features/dashboard/domain/dashboard_snapshot.freezed.dart lib/features/dashboard/application/dashboard_provider.dart lib/features/dashboard/data/dashboard_repository.dart test/unit/dashboard_snapshot_test.dart
git commit -m "feat(dashboard): snapshot porte OnboardingProgress, provider showOnboarding"
```

---

### Task 5: Widget checklist progressif + i18n + câblage page

**Files:**
- Modify: `lib/features/dashboard/presentation/widgets/onboarding_first_steps.dart` (réécriture)
- Modify: `lib/features/dashboard/presentation/dashboard_page.dart` (passer la progression)
- Modify: `lib/l10n/app_fr.arb`, `lib/l10n/app_en.arb`
- Modify: `test/widget/onboarding_first_steps_test.dart` (réécriture)

**Interfaces:**
- Consumes: `OnboardingProgress` (du snapshot), `onboardingDismissedProvider`, clés i18n.

- [ ] **Step 1: Ajouter les clés i18n**

`app_fr.arb` (après les clés onboarding existantes) :

```json
  "dashboardOnboardingSubtitle": "Suivez ces 5 étapes pour démarrer.",
  "dashboardOnboardingStepRecordPaymentLabel": "Enregistrer un paiement",
  "dashboardOnboardingStepGenerateReceiptLabel": "Générer une quittance",
  "dashboardOnboardingProgressLabel": "{done} / {total}",
  "dashboardOnboardingSkip": "Passer",
```

> `dashboardOnboardingSubtitle` existe déjà (« Suivez ces 3 étapes ») — **remplacer** sa valeur par « 5 étapes ». Les autres sont nouvelles.

`app_en.arb` (valeurs + `@description`) :

```json
  "dashboardOnboardingSubtitle": "Follow these 5 steps to get started.",
  "dashboardOnboardingStepRecordPaymentLabel": "Record a payment",
  "@dashboardOnboardingStepRecordPaymentLabel": {
    "description": "Onboarding checklist step 4: navigates to the payment form for the landlord's first lease."
  },
  "dashboardOnboardingStepGenerateReceiptLabel": "Generate a receipt",
  "@dashboardOnboardingStepGenerateReceiptLabel": {
    "description": "Onboarding checklist step 5 (the value moment): navigates to the receipts page of the landlord's first lease."
  },
  "dashboardOnboardingProgressLabel": "{done} / {total}",
  "@dashboardOnboardingProgressLabel": {
    "description": "Onboarding progress indicator, e.g. '2 / 5'.",
    "placeholders": {"done": {"type": "int"}, "total": {"type": "int"}}
  },
  "dashboardOnboardingSkip": "Skip",
  "@dashboardOnboardingSkip": {
    "description": "Link that permanently hides the onboarding checklist on this device."
  },
```

> Adapter au format EXACT du fichier (les clés EN existantes portent déjà `@description`). Ne pas dupliquer une clé existante.

- [ ] **Step 2: gen-l10n** — `flutter gen-l10n`.

- [ ] **Step 3: Réécrire le widget**

`onboarding_first_steps.dart` — devient un `ConsumerWidget` piloté par `OnboardingProgress` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_icon_size.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../application/onboarding_dismissed_provider.dart';
import '../../domain/onboarding_progress.dart';

/// Checklist d'onboarding « Premiers pas », progressive et à état.
///
/// Affichée à la place des KPI tant que le bailleur n'a pas généré sa 1re
/// quittance ([OnboardingProgress.isComplete] == false) et n'a pas « passé »
/// la checklist. Chaque étape est cochée dès que son signal de données est
/// présent. Les étapes 4-5 (paiement, quittance) sont lease-scoped : sans
/// bail ([firstLeaseId] == null), elles sont désactivées.
class OnboardingFirstSteps extends ConsumerWidget {
  const OnboardingFirstSteps({required this.progress, super.key});

  final OnboardingProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;
    final leaseId = progress.firstLeaseId;

    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rocket_launch_outlined,
                  size: AppIconSize.hero,
                  color: theme.colorScheme.primary,
                ),
                const Spacer(),
                Text(
                  l10n.dashboardOnboardingProgressLabel(
                    progress.completedCount,
                    5,
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            Text(l10n.dashboardOnboardingTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              l10n.dashboardOnboardingSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: spacing.xl),
            _StepTile(
              stepNumber: 1,
              label: l10n.dashboardOnboardingStepAddPropertyLabel,
              icon: Icons.home_outlined,
              done: progress.hasProperty,
              route: '/properties/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 2,
              label: l10n.dashboardOnboardingStepAddTenantLabel,
              icon: Icons.person_outline,
              done: progress.hasTenant,
              route: '/tenants/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 3,
              label: l10n.dashboardOnboardingStepCreateLeaseLabel,
              icon: Icons.description_outlined,
              done: progress.hasLease,
              route: '/leases/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 4,
              label: l10n.dashboardOnboardingStepRecordPaymentLabel,
              icon: Icons.payments_outlined,
              done: progress.hasPayment,
              // Lease-scoped : désactivé tant qu'aucun bail.
              route: leaseId == null ? null : '/leases/$leaseId/payments/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 5,
              label: l10n.dashboardOnboardingStepGenerateReceiptLabel,
              icon: Icons.receipt_long_outlined,
              done: progress.hasReceipt,
              route: leaseId == null ? null : '/leases/$leaseId/receipts',
            ),
            SizedBox(height: spacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => ref
                    .read(onboardingDismissedProvider.notifier)
                    .dismiss(),
                child: Text(l10n.dashboardOnboardingSkip),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.stepNumber,
    required this.label,
    required this.icon,
    required this.done,
    required this.route,
  });

  final int stepNumber;
  final String label;
  final IconData icon;
  final bool done;

  /// `null` = étape désactivée (prérequis manquant, ex. pas de bail).
  final String? route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = route == null && !done;

    final leading = done
        ? CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary,
            child: Icon(
              Icons.check,
              size: 18,
              color: theme.colorScheme.onPrimary,
            ),
          )
        : CircleAvatar(
            radius: 16,
            backgroundColor: disabled
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primaryContainer,
            child: Text(
              '$stepNumber',
              style: TextStyle(
                color: disabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          );

    return ListTile(
      enabled: !disabled,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: leading,
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(
          decoration: done ? TextDecoration.lineThrough : null,
          color: done || disabled ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      trailing: done
          ? null
          : Icon(
              Icons.chevron_right,
              color: disabled
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
      // push() : empile le formulaire depuis l'onglet Accueil (docs/UX_NAVIGATION.md §5).
      onTap: route == null ? null : () => context.push(route!),
    );
  }
}
```

- [ ] **Step 4: Câbler `dashboard_page.dart`**

Remplacer :

```dart
    if (snapshot.isOnboarding) {
      return const OnboardingFirstSteps();
    }
```

par :

```dart
    final onboarding = snapshot.onboarding;
    if (onboarding != null) {
      return OnboardingFirstSteps(progress: onboarding);
    }
```

- [ ] **Step 5: Réécrire le test widget**

`test/widget/onboarding_first_steps_test.dart` — monter `OnboardingFirstSteps(progress: …)` dans un `ProviderScope` + `MaterialApp` (avec `localizationsDelegates`). Cas :

```
- 5 tuiles rendues ; libellés des 5 étapes présents.
- progression "2 / 5" affichée quand completedCount==2.
- étape cochée (hasProperty=true) : coche visible / pas de chevron.
- étapes 4-5 désactivées quand firstLeaseId==null (ListTile.enabled==false) ;
  activées quand firstLeaseId!=null.
- tap "Passer" appelle dismiss (vérifier via un override du provider ou l'état).
```

S'aligner sur le harness du test widget existant (mêmes delegates l10n, `ProviderScope`). Garder au moins un cas par invariant ci-dessus.

- [ ] **Step 6: analyze + tests + parité i18n**

Run: `flutter analyze lib/features/dashboard && flutter test test/widget/onboarding_first_steps_test.dart test/l10n/arb_parity_test.dart`
Expected: clean + PASS.

- [ ] **Step 7: Commit**

```bash
dart format lib test/widget/onboarding_first_steps_test.dart
git add lib/features/dashboard/presentation/widgets/onboarding_first_steps.dart lib/features/dashboard/presentation/dashboard_page.dart lib/l10n/app_fr.arb lib/l10n/app_en.arb test/widget/onboarding_first_steps_test.dart
git commit -m "feat(dashboard): checklist onboarding progressive 5 étapes + dismiss"
```

---

### Task 6: Documentation d'état (DoD)

**Files:**
- Modify: `docs/state/routes/dashboard.md`
- Modify: `docs/state/FEATURES.md`
- Modify: `docs/state/CHANGELOG.md`

- [ ] **Step 1: `routes/dashboard.md`** — décrire la checklist progressive (5 étapes dérivées, coches, dismiss local, étapes 4-5 lease-scoped désactivées sans bail, fin = 1re quittance). Mentionner `fetchOnboardingProgress` + `onboardingDismissedProvider`.

- [ ] **Step 2: `FEATURES.md`** — nouvelle ligne FEAT (prochain id libre, domaine dashboard) : « Onboarding progressif jusqu'à la 1re quittance » → ✅ done (réf branche).

- [ ] **Step 3: `CHANGELOG.md`** — entrée en tête de période courante : checklist progressive à état, dérivée des données, dismiss local, 100 % client (aucun backend).

- [ ] **Step 4: Commit**

```bash
git add docs/state/routes/dashboard.md docs/state/FEATURES.md docs/state/CHANGELOG.md
git commit -m "docs(state): onboarding progressif jusqu'à la 1re quittance"
```

---

## Self-Review

- **Spec coverage** : 5 étapes dérivées (Task 1-2), fin=quittance (Task 1 `isComplete`, Task 4 provider), dismiss local (Task 3), checklist principale jusqu'à complétion (Task 4-5), étapes 4-5 lease-scoped désactivées (Task 5), i18n FR/EN (Task 5), docs (Task 6). ✅
- **Placeholder scan** : code complet fourni pour modèle, repo, provider dismiss, snapshot, provider dashboard, widget. Les tests widget (Task 5 Step 5) sont décrits par invariants + cas — l'implémenteur écrit les assertions selon le harness l10n existant (un widget test 100 % verbatim serait fragile face au harness réel ; les invariants sont non ambigus).
- **Type consistency** : `OnboardingProgress` (6 champs + `isComplete`/`completedCount`) cohérent entre Task 1, 2, 4, 5. `firstLeaseId` (String?) alimente les routes 4-5. `DashboardSnapshot.onboarding` (OnboardingProgress?) + getter `isOnboarding` cohérent Task 4/5. `onboardingDismissedProvider` cohérent Task 3/4.
- **Build vert par tâche** : Task 2 additif (garde `isLandlordOnboarding` jusqu'à Task 4 qui le retire proprement) — pas de fenêtre de build cassé.
- **Risque** : mocks de test Firestore/Auth côté Dart — le plan renvoie au harness existant (`dashboard_repository_firestore_test.dart`) pour ne pas introduire de dépendance ni supposer un mock inexistant. À confirmer par l'implémenteur au 1er run de Task 2.
