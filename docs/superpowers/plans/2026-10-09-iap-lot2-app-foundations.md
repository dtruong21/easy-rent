# FEAT-044e lot 2 — Achat intégré : fondations de l'app — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poser, derrière un interrupteur `IAP_ENABLED` coupé par défaut, tout ce dont l'écran d'achat du lot 3 aura besoin : configuration, service d'achat RevenueCat (+ faux pour les tests), synchronisation de l'utilisateur RevenueCat avec la session, et prédicat unique `canOfferUpgrade` sur les textes d'incitation — sans aucun effet visible tant que l'interrupteur est coupé.

**Architecture:** Spec : [`docs/superpowers/specs/2026-10-05-iap-revenuecat-mobile-design.md`](../specs/2026-10-05-iap-revenuecat-mobile-design.md) §1 et §3. Le serveur reste la seule vérité des droits (webhook RevenueCat → Firestore) : l'app ne débloque jamais rien d'après le SDK. Une interface `StoreBillingService` isole le SDK `purchases_flutter` dans une seule classe ; une petite classe sérialise `logIn`/`logOut` selon `sessionStateProvider`. Les textes d'incitation passent de `isStoreApp` à `canOfferUpgrade` (= `!isStoreApp || isInAppPurchaseEnabled`) : interrupteur coupé, comportement strictement identique.

**Tech Stack:** Flutter 3 / Dart ≥ 3.11, Riverpod 2.6 (`Provider`, `StateProvider`), `purchases_flutter` 10.15.2 (RevenueCat), `logging`, `flutter_test`, `firebase_auth_mocks`.

## Global Constraints

- Interrupteur `IAP_ENABLED` (`bool.fromEnvironment`, **défaut `false`**). Coupé : aucun appel au SDK, aucun changement visible, mêmes textes qu'aujourd'hui.
- `isInAppPurchaseEnabled` = `isStoreApp && Env.iapEnabled` **et** clé RevenueCat de la plateforme présente. `canOfferUpgrade` = `!isStoreApp || isInAppPurchaseEnabled`.
- Clés publiques RevenueCat par dart-define : `REVENUECAT_APPLE_API_KEY` (`appl_…`), `REVENUECAT_GOOGLE_API_KEY` (`goog_…`). Jamais committées (seuls les fichiers `dart-defines.*.example.json` sont suivis, valeurs vides). Clé absente alors que l'interrupteur est activé → achat coupé + log `severe`, **jamais de crash**.
- `package:purchases_flutter` n'est importé dans `lib/` **que** par `lib/features/paid_plan/data/revenuecat_store_billing_service.dart` (les tests peuvent l'importer pour ses enums).
- `logIn(uid)` uniquement pour une session `SessionState.fullyAuthenticated` ; jamais pour un anonyme. `logOut()` quand on quitte un compte complet ; jamais de `logOut` si aucun `logIn` n'a eu lieu.
- Prix affichés lus dans le store (`StoreProduct.priceString`), jamais les `priceLabel*` de `PlanMatrix`.
- L'entitlement RevenueCat s'appelle `"Bailan Pro"` (un seul `l`, typo **load-bearing**) : ne jamais le renommer. Ce lot n'en dépend pas (restauration = « au moins un entitlement actif »).
- Ne PAS activer `IAP_ENABLED` avant la fin du lot 3 (la page `/pro` affiche encore le message neutre dans les apps).
- Outillage : `export PATH=/opt/homebrew/bin:$PATH` avant `flutter`/`dart`. `flutter analyze` sans aucun problème ; `dart format` sur les fichiers modifiés ; ne jamais committer `*.g.dart` / `*.freezed.dart` ; ne jamais `git add -A` (chemins explicites) ; ne jamais committer `firebase.altports.local.json`.
- Branche : `feat/044e-iap-app-foundations` depuis `develop`. Commits en français, suffixés de `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

## File Structure

| Fichier | Rôle |
|---|---|
| `lib/core/config/env.dart` (modif) | `iapEnabled`, `revenueCatAppleApiKey`, `revenueCatGoogleApiKey` |
| `lib/core/config/store_billing.dart` (modif) | `revenueCatApiKeyFor`, `isInAppPurchaseEnabled`, `debugInAppPurchaseEnabledOverride`, `canOfferUpgrade` |
| `lib/features/paid_plan/domain/store_billing_models.dart` (nouveau) | `StoreBillingPeriod`, `ProStorePackage`, `ProStoreOffer`, `PurchaseOutcome` (scellée), `RestoreOutcome` |
| `lib/features/paid_plan/data/store_billing_service.dart` (nouveau) | interface `StoreBillingService` + `storeBillingServiceProvider` |
| `lib/features/paid_plan/data/revenuecat_store_billing_service.dart` (nouveau) | seule classe qui importe `purchases_flutter` ; mappers purs testés |
| `lib/features/paid_plan/application/store_billing_session_sync.dart` (nouveau) | `StoreBillingSessionSync` + `storeBillingSessionSyncProvider` |
| `lib/main.dart` (modif) | garde `storeBillingSessionSyncProvider` vivant |
| 7 sites d'incitation (modif) | `isStoreApp` → `canOfferUpgrade` |
| `test/helpers/fake_store_billing_service.dart` (nouveau) | faux service, réutilisé au lot 3 |
| Tests (nouveaux / étendus) | voir chaque tâche |
| Docs | `docs/MOBILE.md`, `docs/STORE_COMPLIANCE.md`, `dart-defines.prod.example.json`, `docs/state/FEATURES.md`, `docs/state/CHANGELOG.md` |

---

### Task 1: Interrupteur et prédicats (`IAP_ENABLED`, `isInAppPurchaseEnabled`, `canOfferUpgrade`)

**Files:**
- Modify: `lib/core/config/env.dart` (dans `class Env`, juste après `subscriptionsEnabled`, ~ligne 170)
- Modify: `lib/core/config/store_billing.dart`
- Test: `test/unit/store_billing_test.dart` (ajout de 2 groupes)

**Interfaces:**
- Produces: `Env.iapEnabled` (`bool`), `Env.revenueCatAppleApiKey` / `Env.revenueCatGoogleApiKey` (`String`, `''` par défaut) ; `String? revenueCatApiKeyFor(TargetPlatform platform, {String appleKey, String googleKey})` ; `bool get isInAppPurchaseEnabled` ; `bool? debugInAppPurchaseEnabledOverride` ; `bool get canOfferUpgrade`.

- [ ] **Step 1: Créer la branche**

```bash
cd /Users/daki.tle/Project/easy-rent && git checkout develop && git pull --ff-only && git checkout -b feat/044e-iap-app-foundations
```

- [ ] **Step 2: Écrire les tests qui échouent** — ajouter à la fin de `main()` de `test/unit/store_billing_test.dart` (le `setUp`/`tearDown` existants restaurent déjà `debugIsStoreAppOverride`) :

```dart
  group('achat intégré (FEAT-044e)', () {
    late bool? originalIap;
    setUp(() => originalIap = debugInAppPurchaseEnabledOverride);
    tearDown(() => debugInAppPurchaseEnabledOverride = originalIap);

    test('sans IAP_ENABLED → achat intégré coupé, même en app store', () {
      debugIsStoreAppOverride = true;
      debugInAppPurchaseEnabledOverride = null;
      expect(isInAppPurchaseEnabled, isFalse);
    });

    test('canOfferUpgrade : web → vrai (parcours Stripe)', () {
      debugIsStoreAppOverride = false;
      debugInAppPurchaseEnabledOverride = null;
      expect(canOfferUpgrade, isTrue);
    });

    test('canOfferUpgrade : app store sans achat intégré → faux', () {
      debugIsStoreAppOverride = true;
      debugInAppPurchaseEnabledOverride = false;
      expect(canOfferUpgrade, isFalse);
    });

    test('canOfferUpgrade : app store avec achat intégré → vrai', () {
      debugIsStoreAppOverride = true;
      debugInAppPurchaseEnabledOverride = true;
      expect(canOfferUpgrade, isTrue);
    });
  });

  group('revenueCatApiKeyFor', () {
    test('iOS → clé Apple', () {
      expect(
        revenueCatApiKeyFor(
          TargetPlatform.iOS,
          appleKey: 'appl_x',
          googleKey: 'goog_y',
        ),
        'appl_x',
      );
    });

    test('Android → clé Google', () {
      expect(
        revenueCatApiKeyFor(
          TargetPlatform.android,
          appleKey: 'appl_x',
          googleKey: 'goog_y',
        ),
        'goog_y',
      );
    });

    test('clé vide ou blanche → null', () {
      expect(
        revenueCatApiKeyFor(TargetPlatform.iOS, appleKey: '  ', googleKey: ''),
        isNull,
      );
    });

    test('plateforme sans achat intégré → null', () {
      expect(
        revenueCatApiKeyFor(
          TargetPlatform.macOS,
          appleKey: 'appl_x',
          googleKey: 'goog_y',
        ),
        isNull,
      );
    });

    test('sans dart-define → null', () {
      expect(revenueCatApiKeyFor(TargetPlatform.iOS), isNull);
      expect(revenueCatApiKeyFor(TargetPlatform.android), isNull);
    });
  });
```

- [ ] **Step 3: Vérifier qu'ils échouent**

Run: `export PATH=/opt/homebrew/bin:$PATH && flutter test test/unit/store_billing_test.dart`
Expected: échec de compilation (`isInAppPurchaseEnabled`, `canOfferUpgrade`, `revenueCatApiKeyFor`, `debugInAppPurchaseEnabledOverride` non définis).

- [ ] **Step 4: Implémenter** — dans `class Env` (`lib/core/config/env.dart`), après la déclaration de `subscriptionsEnabled` :

```dart
  /// FEAT-044e — achat intégré (RevenueCat) dans les apps iOS/Android. Coupé
  /// par défaut : sans `--dart-define=IAP_ENABLED=true`, une app store garde
  /// le comportement actuel (aucun achat, aucune incitation). Sans effet sur
  /// le web (Stripe, cf. [subscriptionsEnabled]). Ne pas l'activer avant le
  /// lot 3 (écran d'achat).
  static const bool iapEnabled = bool.fromEnvironment(
    'IAP_ENABLED',
    defaultValue: false,
  );

  /// Clé SDK RevenueCat iOS (`appl_…`) — publique par nature (clé client).
  static const String revenueCatAppleApiKey = String.fromEnvironment(
    'REVENUECAT_APPLE_API_KEY',
  );

  /// Clé SDK RevenueCat Android (`goog_…`) — publique par nature.
  static const String revenueCatGoogleApiKey = String.fromEnvironment(
    'REVENUECAT_GOOGLE_API_KEY',
  );
```

Puis dans `lib/core/config/store_billing.dart`, ajouter l'import `import 'env.dart';` sous l'import existant et, à la fin du fichier :

```dart
/// Clé SDK RevenueCat de [platform], ou `null` si absente ou si la plateforme
/// n'a pas d'achat intégré. Valeurs par défaut : dart-defines ; injectables
/// pour les tests.
String? revenueCatApiKeyFor(
  TargetPlatform platform, {
  String appleKey = Env.revenueCatAppleApiKey,
  String googleKey = Env.revenueCatGoogleApiKey,
}) {
  final key = switch (platform) {
    TargetPlatform.iOS => appleKey,
    TargetPlatform.android => googleKey,
    _ => '',
  }.trim();
  return key.isEmpty ? null : key;
}

/// FEAT-044e — achat intégré actif : app store + `IAP_ENABLED` + clé
/// RevenueCat de la plateforme. Clé absente : achat coupé (journalisé par le
/// service au démarrage), jamais de crash.
bool get isInAppPurchaseEnabled =>
    debugInAppPurchaseEnabledOverride ??
    (isStoreApp &&
        Env.iapEnabled &&
        revenueCatApiKeyFor(defaultTargetPlatform) != null);

/// Forçage pour les tests.
@visibleForTesting
bool? debugInAppPurchaseEnabledOverride;

/// Prédicat UNIQUE des textes d'incitation (« Passez à Pro… », CTA vers
/// `/pro`) : vrai sur le web (Stripe) et dans une app store dont l'achat
/// intégré est actif ; faux dans une app store sans achat intégré (App Store
/// 3.1.1, règle Paiements de Google Play).
bool get canOfferUpgrade => !isStoreApp || isInAppPurchaseEnabled;
```

- [ ] **Step 5: Vérifier que les tests passent**

Run: `flutter test test/unit/store_billing_test.dart && dart format lib/core/config test/unit/store_billing_test.dart && flutter analyze lib/core/config test/unit/store_billing_test.dart`
Expected: tous les tests PASS ; « No issues found! ».

- [ ] **Step 6: Commit**

```bash
git add lib/core/config/env.dart lib/core/config/store_billing.dart test/unit/store_billing_test.dart
git commit -m "feat(iap): interrupteur IAP_ENABLED et prédicat canOfferUpgrade (FEAT-044e lot 2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Service d'achat — modèles, interface, implémentation RevenueCat

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock` (via `flutter pub add`)
- Create: `lib/features/paid_plan/domain/store_billing_models.dart`
- Create: `lib/features/paid_plan/data/store_billing_service.dart`
- Create: `lib/features/paid_plan/data/revenuecat_store_billing_service.dart`
- Create: `test/helpers/fake_store_billing_service.dart`
- Test: `test/unit/revenuecat_store_billing_service_test.dart`

**Interfaces:**
- Consumes: `isStoreApp`, `Env.iapEnabled`, `revenueCatApiKeyFor` (Task 1).
- Produces: `enum StoreBillingPeriod { monthly, annual }` ; `ProStorePackage({required StoreBillingPeriod period, required String priceString})` ; `ProStoreOffer({ProStorePackage? monthly, ProStorePackage? annual})` ; `sealed class PurchaseOutcome` avec `PurchaseSucceeded()`, `PurchaseCancelled()`, `PurchasePending()`, `PurchaseFailed(String code)` ; `enum RestoreOutcome { success, nothingToRestore, error }` ; `abstract interface class StoreBillingService` (méthodes ci-dessous) ; `final storeBillingServiceProvider = Provider<StoreBillingService>` ; `class FakeStoreBillingService implements StoreBillingService` (test) avec `List<String> calls`, `Completer<void>? logInGate`, `Object? logInError`, `ProStoreOffer? offer`, `PurchaseOutcome purchaseOutcome`, `RestoreOutcome restoreOutcome`, `Uri? management`.

- [ ] **Step 1: Ajouter la dépendance**

Run: `flutter pub add purchases_flutter:^10.15.2`
Expected: `pubspec.yaml` contient `purchases_flutter: ^10.15.2`. Lire l'API réelle dans `~/.pub-cache/hosted/pub.dev/purchases_flutter-10.15.2/lib/` si un nom ci-dessous ne compile pas (vérifié au moment du plan : `Purchases.configure(PurchasesConfiguration(key))`, `Purchases.logIn(uid)`, `Purchases.logOut()`, `Purchases.getOfferings()` → `Offerings.current` → `Offering.monthly` / `.annual` (`Package?`), `Package.storeProduct.priceString`, `Purchases.purchase(PurchaseParams.package(package))`, `Purchases.restorePurchases()` / `getCustomerInfo()` → `CustomerInfo.entitlements.active` (`Map`) et `.managementURL` (`String?`), `PurchasesErrorHelper.getErrorCode(PlatformException)` → `PurchasesErrorCode.purchaseCancelledError` / `.paymentPendingError` / `.logOutWithAnonymousUserError`).

- [ ] **Step 2: Écrire les modèles** — `lib/features/paid_plan/domain/store_billing_models.dart` :

```dart
/// Modèles de l'achat intégré (FEAT-044e). Indépendants de
/// `purchases_flutter` : seul `RevenueCatStoreBillingService` importe le SDK.
library;

/// Périodicité d'une formule du store.
enum StoreBillingPeriod { monthly, annual }

/// Une formule achetable. [priceString] est LU DANS LE STORE (localisé) —
/// jamais les `priceLabel*` figés de `PlanMatrix`.
class ProStorePackage {
  const ProStorePackage({required this.period, required this.priceString});

  final StoreBillingPeriod period;
  final String priceString;
}

/// Offre Pro courante du store.
class ProStoreOffer {
  const ProStoreOffer({this.monthly, this.annual});

  final ProStorePackage? monthly;
  final ProStorePackage? annual;
}

/// Issue d'un achat. Le droit lui-même arrive par le serveur (webhook
/// RevenueCat → Firestore), jamais d'après cette issue.
sealed class PurchaseOutcome {
  const PurchaseOutcome();
}

final class PurchaseSucceeded extends PurchaseOutcome {
  const PurchaseSucceeded();
}

final class PurchaseCancelled extends PurchaseOutcome {
  const PurchaseCancelled();
}

/// Contrôle parental, paiement différé : ni succès ni échec.
final class PurchasePending extends PurchaseOutcome {
  const PurchasePending();
}

final class PurchaseFailed extends PurchaseOutcome {
  const PurchaseFailed(this.code);

  /// Code technique (nom du `PurchasesErrorCode`, ou `not_configured` /
  /// `package_unavailable`) — journal et support, jamais affiché tel quel.
  final String code;
}

/// Issue de « Restaurer les achats ».
enum RestoreOutcome { success, nothingToRestore, error }
```

- [ ] **Step 3: Écrire l'interface** — `lib/features/paid_plan/data/store_billing_service.dart` :

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/store_billing_models.dart';
import 'revenuecat_store_billing_service.dart';

/// Achat intégré des apps iOS/Android (FEAT-044e). Toutes les méthodes sont
/// sans effet (ou rendent une issue neutre) tant que le service n'est pas
/// configuré — c'est-à-dire tant que l'achat intégré est coupé.
abstract interface class StoreBillingService {
  /// Une fois, au démarrage. Sans effet si l'achat intégré est coupé.
  Future<void> configure();

  /// Rattache les achats au compte [uid] (compte complet uniquement).
  Future<void> logIn(String uid);

  /// Détache le compte courant (déconnexion, passage anonyme).
  Future<void> logOut();

  /// Offre Pro courante, prix lus dans le store ; `null` si indisponible.
  Future<ProStoreOffer?> fetchProOffer();

  Future<PurchaseOutcome> purchase(ProStorePackage package);

  Future<RestoreOutcome> restore();

  /// Page de gestion de l'abonnement dans le store, si connue.
  Future<Uri?> managementUrl();
}

final storeBillingServiceProvider = Provider<StoreBillingService>(
  (ref) => RevenueCatStoreBillingService(),
);
```

- [ ] **Step 4: Écrire les tests qui échouent** — `test/unit/revenuecat_store_billing_service_test.dart` :

```dart
/// Tests de [RevenueCatStoreBillingService] : mappers purs et comportement
/// « non configuré » (achat intégré coupé dans `flutter test` : IAP_ENABLED
/// absent, donc aucun appel au SDK).
library;

import 'package:easyrent/features/paid_plan/data/revenuecat_store_billing_service.dart';
import 'package:easyrent/features/paid_plan/data/store_billing_service.dart';
import 'package:easyrent/features/paid_plan/domain/store_billing_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

void main() {
  group('purchaseOutcomeForError', () {
    test('annulation → PurchaseCancelled', () {
      expect(
        purchaseOutcomeForError(PurchasesErrorCode.purchaseCancelledError),
        isA<PurchaseCancelled>(),
      );
    });

    test('paiement en attente → PurchasePending', () {
      expect(
        purchaseOutcomeForError(PurchasesErrorCode.paymentPendingError),
        isA<PurchasePending>(),
      );
    });

    test('autre erreur → PurchaseFailed avec le nom du code', () {
      for (final code in [
        PurchasesErrorCode.storeProblemError,
        PurchasesErrorCode.networkError,
        PurchasesErrorCode.productAlreadyPurchasedError,
      ]) {
        expect(
          purchaseOutcomeForError(code),
          isA<PurchaseFailed>().having((f) => f.code, 'code', code.name),
        );
      }
    });
  });

  group('restoreOutcomeFor', () {
    test('aucun entitlement actif → nothingToRestore', () {
      expect(
        restoreOutcomeFor(activeEntitlements: 0),
        RestoreOutcome.nothingToRestore,
      );
    });

    test('au moins un entitlement actif → success', () {
      expect(restoreOutcomeFor(activeEntitlements: 1), RestoreOutcome.success);
    });
  });

  group('achat intégré coupé (non configuré)', () {
    late RevenueCatStoreBillingService service;
    setUp(() async {
      service = RevenueCatStoreBillingService();
      await service.configure(); // sans effet : IAP_ENABLED absent
    });

    test('offre → null', () async {
      expect(await service.fetchProOffer(), isNull);
    });

    test('achat → PurchaseFailed(not_configured)', () async {
      final outcome = await service.purchase(
        const ProStorePackage(
          period: StoreBillingPeriod.monthly,
          priceString: '7,99 €',
        ),
      );
      expect(
        outcome,
        isA<PurchaseFailed>().having((f) => f.code, 'code', 'not_configured'),
      );
    });

    test('restauration → error', () async {
      expect(await service.restore(), RestoreOutcome.error);
    });

    test('page de gestion → null', () async {
      expect(await service.managementUrl(), isNull);
    });

    test('logIn / logOut → sans effet ni exception', () async {
      await service.logIn('u1');
      await service.logOut();
    });
  });

  test('le provider fournit le service RevenueCat', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(storeBillingServiceProvider),
      isA<RevenueCatStoreBillingService>(),
    );
  });
}
```

- [ ] **Step 5: Vérifier qu'ils échouent**

Run: `flutter test test/unit/revenuecat_store_billing_service_test.dart`
Expected: échec de compilation (`revenuecat_store_billing_service.dart` absent).

- [ ] **Step 6: Implémenter** — `lib/features/paid_plan/data/revenuecat_store_billing_service.dart` :

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/config/store_billing.dart';
import '../domain/store_billing_models.dart';
import 'store_billing_service.dart';

final _log = Logger('RevenueCatStoreBillingService');

/// PURE — issue d'un achat selon le code d'erreur du SDK.
@visibleForTesting
PurchaseOutcome purchaseOutcomeForError(PurchasesErrorCode code) =>
    switch (code) {
      PurchasesErrorCode.purchaseCancelledError => const PurchaseCancelled(),
      PurchasesErrorCode.paymentPendingError => const PurchasePending(),
      _ => PurchaseFailed(code.name),
    };

/// PURE — restauration : au moins un entitlement actif → droit retrouvé
/// (le palier lui-même vient du serveur).
@visibleForTesting
RestoreOutcome restoreOutcomeFor({required int activeEntitlements}) =>
    activeEntitlements > 0
    ? RestoreOutcome.success
    : RestoreOutcome.nothingToRestore;

/// Implémentation RevenueCat — SEULE classe de `lib/` qui importe
/// `purchases_flutter`. Non configurée (achat intégré coupé, clé absente,
/// échec du SDK) : chaque méthode est sans effet ou rend une issue neutre.
class RevenueCatStoreBillingService implements StoreBillingService {
  bool _configured = false;

  @override
  Future<void> configure() async {
    if (_configured || !isStoreApp || !Env.iapEnabled) return;
    final key = revenueCatApiKeyFor(defaultTargetPlatform);
    if (key == null) {
      _log.severe(
        'IAP_ENABLED sans clé RevenueCat pour $defaultTargetPlatform : '
        'achat intégré coupé',
      );
      return;
    }
    try {
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
    } catch (e, st) {
      _log.severe('configuration RevenueCat impossible : achat coupé', e, st);
    }
  }

  @override
  Future<void> logIn(String uid) async {
    if (!_configured) return;
    try {
      await Purchases.logIn(uid);
    } catch (e, st) {
      _log.warning('logIn RevenueCat échoué', e, st);
    }
  }

  @override
  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } on PlatformException catch (e, st) {
      // Utilisateur déjà anonyme côté RevenueCat : rien à faire.
      if (PurchasesErrorHelper.getErrorCode(e) !=
          PurchasesErrorCode.logOutWithAnonymousUserError) {
        _log.warning('logOut RevenueCat échoué', e, st);
      }
    }
  }

  @override
  Future<ProStoreOffer?> fetchProOffer() async {
    if (!_configured) return null;
    try {
      final current = (await Purchases.getOfferings()).current;
      if (current == null) return null;
      ProStorePackage? map(Package? p, StoreBillingPeriod period) => p == null
          ? null
          : ProStorePackage(
              period: period,
              priceString: p.storeProduct.priceString,
            );
      return ProStoreOffer(
        monthly: map(current.monthly, StoreBillingPeriod.monthly),
        annual: map(current.annual, StoreBillingPeriod.annual),
      );
    } catch (e, st) {
      _log.warning('offres RevenueCat indisponibles', e, st);
      return null;
    }
  }

  @override
  Future<PurchaseOutcome> purchase(ProStorePackage package) async {
    if (!_configured) return const PurchaseFailed('not_configured');
    try {
      final current = (await Purchases.getOfferings()).current;
      final pkg = switch (package.period) {
        StoreBillingPeriod.monthly => current?.monthly,
        StoreBillingPeriod.annual => current?.annual,
      };
      if (pkg == null) return const PurchaseFailed('package_unavailable');
      await Purchases.purchase(PurchaseParams.package(pkg));
      return const PurchaseSucceeded();
    } on PlatformException catch (e) {
      return purchaseOutcomeForError(PurchasesErrorHelper.getErrorCode(e));
    }
  }

  @override
  Future<RestoreOutcome> restore() async {
    if (!_configured) return RestoreOutcome.error;
    try {
      final info = await Purchases.restorePurchases();
      return restoreOutcomeFor(
        activeEntitlements: info.entitlements.active.length,
      );
    } catch (e, st) {
      _log.warning('restauration RevenueCat échouée', e, st);
      return RestoreOutcome.error;
    }
  }

  @override
  Future<Uri?> managementUrl() async {
    if (!_configured) return null;
    try {
      final url = (await Purchases.getCustomerInfo()).managementURL;
      return url == null ? null : Uri.tryParse(url);
    } catch (e, st) {
      _log.warning('URL de gestion RevenueCat indisponible', e, st);
      return null;
    }
  }
}
```

- [ ] **Step 7: Écrire le faux service** (réutilisé par la Task 3 et le lot 3) — `test/helpers/fake_store_billing_service.dart` :

```dart
import 'dart:async';

import 'package:easyrent/features/paid_plan/data/store_billing_service.dart';
import 'package:easyrent/features/paid_plan/domain/store_billing_models.dart';

/// Faux [StoreBillingService] : journalise chaque appel dans [calls] et rend
/// les issues configurées. [logInGate] retient `logIn` jusqu'à sa complétion
/// (tests de sérialisation) ; [logInError] fait échouer `logIn`.
class FakeStoreBillingService implements StoreBillingService {
  final List<String> calls = [];
  Completer<void>? logInGate;
  Object? logInError;
  ProStoreOffer? offer;
  PurchaseOutcome purchaseOutcome = const PurchaseSucceeded();
  RestoreOutcome restoreOutcome = RestoreOutcome.nothingToRestore;
  Uri? management;

  @override
  Future<void> configure() async => calls.add('configure');

  @override
  Future<void> logIn(String uid) async {
    calls.add('logIn:$uid');
    if (logInGate != null) await logInGate!.future;
    if (logInError != null) throw logInError!;
  }

  @override
  Future<void> logOut() async => calls.add('logOut');

  @override
  Future<ProStoreOffer?> fetchProOffer() async {
    calls.add('fetchProOffer');
    return offer;
  }

  @override
  Future<PurchaseOutcome> purchase(ProStorePackage package) async {
    calls.add('purchase:${package.period.name}');
    return purchaseOutcome;
  }

  @override
  Future<RestoreOutcome> restore() async {
    calls.add('restore');
    return restoreOutcome;
  }

  @override
  Future<Uri?> managementUrl() async {
    calls.add('managementUrl');
    return management;
  }
}
```

- [ ] **Step 8: Vérifier que les tests passent et que le SDK reste confiné**

Run:
```bash
flutter test test/unit/revenuecat_store_billing_service_test.dart
dart format lib/features/paid_plan test/unit/revenuecat_store_billing_service_test.dart test/helpers/fake_store_billing_service.dart
flutter analyze lib/features/paid_plan test/unit/revenuecat_store_billing_service_test.dart test/helpers
grep -rln "package:purchases_flutter" lib
```
Expected: tests PASS ; « No issues found! » ; le `grep` ne liste QUE `lib/features/paid_plan/data/revenuecat_store_billing_service.dart`.

- [ ] **Step 9: Vérifier que le web et Android compilent avec le plugin**

Run:
```bash
flutter build web --release --pwa-strategy=none
flutter build apk --debug
```
Expected: les deux builds réussissent (le web ne configure jamais le SDK : `isStoreApp` est faux). Si `flutter build apk` est impossible localement (SDK Android absent), le noter dans le rapport : le workflow CI « Mobile » construit l'APK debug sur la PR.

- [ ] **Step 10: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/paid_plan/domain/store_billing_models.dart lib/features/paid_plan/data/store_billing_service.dart lib/features/paid_plan/data/revenuecat_store_billing_service.dart test/helpers/fake_store_billing_service.dart test/unit/revenuecat_store_billing_service_test.dart
git commit -m "feat(iap): service d'achat RevenueCat derrière une interface (FEAT-044e lot 2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Utilisateur RevenueCat aligné sur la session (`logIn` / `logOut`)

**Files:**
- Create: `lib/features/paid_plan/application/store_billing_session_sync.dart`
- Modify: `lib/main.dart` (méthode `build` de `_BaillanAppState`)
- Test: `test/unit/store_billing_session_sync_test.dart`

**Interfaces:**
- Consumes: `StoreBillingService`, `storeBillingServiceProvider` (Task 2) ; `isInAppPurchaseEnabled`, `debugInAppPurchaseEnabledOverride` (Task 1) ; `sessionStateProvider` (`lib/features/auth/application/auth_session_provider.dart`) ; `authRepositoryProvider` + `AuthRepository.currentUser` (`lib/features/auth/data/auth_repository.dart`) ; `SessionState` (`lib/features/auth/domain/session_state.dart`) ; `FakeStoreBillingService` (`test/helpers/`).
- Produces: `class StoreBillingSessionSync` avec `Future<void> onSession(SessionState state, String? uid)` ; `final storeBillingSessionSyncProvider = Provider<void>`.

- [ ] **Step 1: Écrire les tests qui échouent** — `test/unit/store_billing_session_sync_test.dart` :

```dart
/// Tests de [StoreBillingSessionSync] et de son câblage Riverpod (FEAT-044e) :
/// `logIn` pour un compte complet seulement, `logOut` en le quittant, appels
/// sérialisés, rien du tout quand l'achat intégré est coupé.
library;

import 'dart:async';

import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:easyrent/features/paid_plan/application/store_billing_session_sync.dart';
import 'package:easyrent/features/paid_plan/data/store_billing_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_store_billing_service.dart';

const _full = SessionState.fullyAuthenticated;
const _anon = SessionState.anonymous;
const _out = SessionState.unauthenticated;

/// Repository d'auth réduit à `currentUser` (le reste n'est jamais appelé).
class _FakeAuthRepo implements AuthRepository {
  _FakeAuthRepo(this.currentUser);

  @override
  final User? currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeStoreBillingService fake;
  late StoreBillingSessionSync sync;

  setUp(() {
    fake = FakeStoreBillingService();
    sync = StoreBillingSessionSync(fake);
  });

  test('compte complet → configure une fois, puis logIn', () async {
    await sync.onSession(_full, 'u1');
    expect(fake.calls, ['configure', 'logIn:u1']);
  });

  test('même compte répété → un seul logIn', () async {
    await sync.onSession(_full, 'u1');
    await sync.onSession(_full, 'u1');
    expect(fake.calls, ['configure', 'logIn:u1']);
  });

  test('anonyme → jamais de logIn', () async {
    await sync.onSession(_anon, 'anon-1');
    expect(fake.calls, ['configure']);
  });

  test('non connecté au démarrage → pas de logOut', () async {
    await sync.onSession(_out, null);
    expect(fake.calls, ['configure']);
  });

  test('déconnexion après un compte complet → logOut', () async {
    await sync.onSession(_full, 'u1');
    await sync.onSession(_out, null);
    expect(fake.calls, ['configure', 'logIn:u1', 'logOut']);
  });

  test('compte complet puis anonyme → logOut', () async {
    await sync.onSession(_full, 'u1');
    await sync.onSession(_anon, 'anon-1');
    expect(fake.calls.last, 'logOut');
  });

  test('changement de compte → logOut puis logIn du nouveau', () async {
    await sync.onSession(_full, 'u1');
    await sync.onSession(_out, null);
    await sync.onSession(_full, 'u2');
    expect(fake.calls, ['configure', 'logIn:u1', 'logOut', 'logIn:u2']);
  });

  test('appels sérialisés : logOut attend la fin du logIn', () async {
    fake.logInGate = Completer<void>();
    final first = sync.onSession(_full, 'u1');
    final second = sync.onSession(_out, null);
    await pumpEventQueue();
    expect(fake.calls, ['configure', 'logIn:u1']);

    fake.logInGate!.complete();
    await Future.wait([first, second]);
    expect(fake.calls, ['configure', 'logIn:u1', 'logOut']);
  });

  test('échec de logIn → aucune exception, l\'état suivant réessaie', () async {
    fake.logInError = StateError('réseau');
    await sync.onSession(_full, 'u1');
    fake.logInError = null;
    await sync.onSession(_full, 'u1');
    expect(fake.calls, ['configure', 'logIn:u1', 'logIn:u1']);
  });

  group('storeBillingSessionSyncProvider', () {
    late StateProvider<SessionState> session;
    late ProviderContainer container;

    ProviderContainer build() {
      session = StateProvider<SessionState>((_) => _full);
      final c = ProviderContainer(
        overrides: [
          storeBillingServiceProvider.overrideWithValue(fake),
          sessionStateProvider.overrideWith((ref) => ref.watch(session)),
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepo(MockUser(uid: 'u1', isEmailVerified: true)),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    tearDown(() => debugInAppPurchaseEnabledOverride = null);

    test('achat intégré coupé → aucun appel au service', () async {
      debugInAppPurchaseEnabledOverride = false;
      container = build();
      container.read(storeBillingSessionSyncProvider);
      await pumpEventQueue();
      expect(fake.calls, isEmpty);
    });

    test('achat intégré actif → logIn de l\'uid courant, logOut à la '
        'déconnexion', () async {
      debugInAppPurchaseEnabledOverride = true;
      container = build();
      container.read(storeBillingSessionSyncProvider);
      await pumpEventQueue();
      expect(fake.calls, ['configure', 'logIn:u1']);

      container.read(session.notifier).state = _out;
      await pumpEventQueue();
      expect(fake.calls.last, 'logOut');
    });
  });
}
```

- [ ] **Step 2: Vérifier qu'ils échouent**

Run: `flutter test test/unit/store_billing_session_sync_test.dart`
Expected: échec de compilation (`store_billing_session_sync.dart` absent).

- [ ] **Step 3: Implémenter** — `lib/features/paid_plan/application/store_billing_session_sync.dart` :

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/store_billing.dart';
import '../../auth/application/auth_session_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/session_state.dart';
import '../data/store_billing_service.dart';

final _log = Logger('StoreBillingSessionSync');

/// Aligne l'utilisateur RevenueCat sur la session Firebase (FEAT-044e) :
/// `logIn(uid)` pour un compte COMPLET uniquement, `logOut()` en le quittant.
/// Jamais de `logIn` pour un anonyme : son achat serait rattaché à un uid que
/// la purge des anonymes supprime. Configure le service au premier état reçu.
/// Les appels sont sérialisés : un `logOut` ne double jamais un `logIn` en
/// cours.
class StoreBillingSessionSync {
  StoreBillingSessionSync(this._service);

  final StoreBillingService _service;
  Future<void> _queue = Future.value();
  bool _configured = false;
  String? _loggedInUid;

  Future<void> onSession(SessionState state, String? uid) {
    final target = state == SessionState.fullyAuthenticated ? uid : null;
    return _queue = _queue
        .then((_) => _apply(target))
        .catchError((Object e, StackTrace st) {
          _log.warning('synchronisation RevenueCat échouée', e, st);
        });
  }

  Future<void> _apply(String? target) async {
    if (!_configured) {
      _configured = true;
      await _service.configure();
    }
    if (target == _loggedInUid) return;
    if (target == null) {
      await _service.logOut();
    } else {
      await _service.logIn(target);
    }
    _loggedInUid = target;
  }
}

/// Branche [StoreBillingSessionSync] sur [sessionStateProvider]. Inerte
/// (aucun appel au SDK) tant que l'achat intégré est coupé. Gardé vivant par
/// `BaillanApp`.
final storeBillingSessionSyncProvider = Provider<void>((ref) {
  if (!isInAppPurchaseEnabled) return;
  final sync = StoreBillingSessionSync(ref.watch(storeBillingServiceProvider));
  ref.listen<SessionState>(sessionStateProvider, (_, state) {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    unawaited(sync.onSession(state, uid));
  }, fireImmediately: true);
});
```

- [ ] **Step 4: Brancher dans l'app** — dans `lib/main.dart`, `_BaillanAppState.build`, juste après `final router = ref.watch(appRouterProvider);` :

```dart
    // FEAT-044e : utilisateur RevenueCat aligné sur la session (inerte tant
    // que l'achat intégré est coupé).
    ref.watch(storeBillingSessionSyncProvider);
```

et l'import correspondant, à sa place alphabétique parmi les imports `features/` de `main.dart` :

```dart
import 'features/paid_plan/application/store_billing_session_sync.dart';
```

- [ ] **Step 5: Vérifier que les tests passent**

Run: `flutter test test/unit/store_billing_session_sync_test.dart && dart format lib/features/paid_plan lib/main.dart test/unit/store_billing_session_sync_test.dart && flutter analyze lib test/unit/store_billing_session_sync_test.dart`
Expected: tests PASS ; « No issues found! ».

- [ ] **Step 6: Commit**

```bash
git add lib/features/paid_plan/application/store_billing_session_sync.dart lib/main.dart test/unit/store_billing_session_sync_test.dart
git commit -m "feat(iap): utilisateur RevenueCat aligné sur la session — comptes complets seulement (FEAT-044e lot 2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `canOfferUpgrade` sur les textes d'incitation

**Files (7 sites, `isStoreApp` → `canOfferUpgrade`) :**
- Modify: `lib/features/properties/presentation/property_submit_error_l10n.dart` (~l.19-22)
- Modify: `lib/features/tenants/presentation/tenant_submit_error_l10n.dart` (~l.17-20)
- Modify: `lib/features/leases/presentation/lease_submit_error_l10n.dart` (~l.25-28)
- Modify: `lib/features/documents/presentation/upload_file_error_reason_l10n.dart` (~l.36-38)
- Modify: `lib/features/simulator/presentation/widgets/scenario_limit_reached_modal.dart` (~l.63, + doc l.20)
- Modify: `lib/features/simulator/presentation/scenario_comparison_page.dart` (~l.76-78)
- Modify: `lib/features/simulator/presentation/widgets/saved_scenarios_row.dart` (~l.299-301)
- Test: `test/widget/upsell_messages_store_test.dart` (nouveau) ; ajouts dans `test/widget/scenario_limit_modal_test.dart`, `test/widget/scenario_comparison_page_test.dart`, `test/widget/saved_scenarios_row_test.dart`

**Interfaces:**
- Consumes: `canOfferUpgrade`, `debugInAppPurchaseEnabledOverride` (Task 1).

**Hors périmètre (ne pas toucher) :** `simulator_page.dart` (`ComingSoonPaidPlanSection`, contenu « bientôt »), `profile_page.dart` (bannière « Passer à Pro »), `pro_pricing_page.dart`, `pro_cancel_page.dart`, `subscription_section.dart` → lot 3 ; `charge_regularization_section.dart` (texte sans lien ni garde aujourd'hui).

- [ ] **Step 1: Écrire les tests qui échouent — messages.** Lire d'abord les 4 fichiers `*_l10n.dart` ci-dessus pour connaître le nom exact de chaque méthode d'extension et ses paramètres (`PropertySubmitError.limitReached.message(context)` a été vérifié ; vérifier tenants, leases et `UploadFileErrorReason` — paramètres nommés `maxFileSizeBytes`, `serverLimitBytes`, `serverUpgradeToLevelId`). Créer `test/widget/upsell_messages_store_test.dart` qui, pour chacun des 4 messages, vérifie les 3 cas ci-dessous en comparant aux chaînes de `AppLocalizations` (locale `fr`, via `lookupAppLocalizations(const Locale('fr'))`, jamais en dur) :

| Cas | `debugIsStoreAppOverride` | `debugInAppPurchaseEnabledOverride` | Attendu |
|---|---|---|---|
| web | `false` | `null` | variante avec incitation (`propertiesErrorLimitReached`, `tenantsErrorLimitReached`, `leasesErrorLimitReached`, `documentsUploadErrorFileTooLargeWithUpgrade`) |
| app store, achat coupé | `true` | `false` | variante neutre (`…LimitReachedStore` ; `documentsUploadErrorFileTooLarge`) |
| app store, achat actif | `true` | `true` | variante avec incitation |

Squelette (à répéter pour les 4 messages, un `group` chacun) :

```dart
import 'package:easyrent/core/config/store_billing.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/properties/domain/property_submit_error.dart';
import 'package:easyrent/features/properties/presentation/property_submit_error_l10n.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rend le message calculé par [compute] dans un contexte localisé `fr`.
Future<String> _message(
  WidgetTester tester,
  String Function(BuildContext context) compute,
) async {
  late String result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
      home: Builder(
        builder: (context) {
          result = compute(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('fr'));

  tearDown(() {
    debugIsStoreAppOverride = false;
    debugInAppPurchaseEnabledOverride = null;
  });

  group('biens — limite atteinte', () {
    String compute(BuildContext c) => PropertySubmitError.limitReached.message(c);

    testWidgets('web → incitation', (tester) async {
      debugIsStoreAppOverride = false;
      expect(await _message(tester, compute), l10n.propertiesErrorLimitReached);
    });

    testWidgets('app store, achat coupé → message neutre', (tester) async {
      debugIsStoreAppOverride = true;
      debugInAppPurchaseEnabledOverride = false;
      expect(
        await _message(tester, compute),
        l10n.propertiesErrorLimitReachedStore,
      );
    });

    testWidgets('app store, achat actif → incitation', (tester) async {
      debugIsStoreAppOverride = true;
      debugInAppPurchaseEnabledOverride = true;
      expect(await _message(tester, compute), l10n.propertiesErrorLimitReached);
    });
  });

  // … mêmes 3 cas pour locataires, baux et document trop volumineux
  // (serverUpgradeToLevelId: 'pro'). Pour le document, l'attendu
  // « incitation » se calcule avec la même taille et le libellé du palier que
  // le code (lire upload_file_error_reason_l10n.dart) ; à défaut, vérifier
  // `contains` sur le libellé du palier « Pro » pour l'incitation et son
  // absence pour la variante neutre.
}
```

Ajuster les imports `domain/` à l'emplacement réel de chaque enum (`grep -rn "enum PropertySubmitError\|enum TenantSubmitError\|enum LeaseSubmitError\|enum UploadFileErrorReason" lib`).

- [ ] **Step 2: Écrire les tests qui échouent — CTA.** Dans chacun des 3 fichiers de test existants, le groupe « app store » (`setUp(() => debugIsStoreAppOverride = true)`, vers `scenario_limit_modal_test.dart:266`, `scenario_comparison_page_test.dart:362`, `saved_scenarios_row_test.dart:274`) vérifie déjà l'ABSENCE du CTA. Y ajouter un test jumeau qui pose `debugInAppPurchaseEnabledOverride = true` (remis à `null` dans un `addTearDown`), reprend exactement le même montage que le test d'absence voisin, et vérifie la PRÉSENCE du même élément : bouton `scenario_limit_upgrade_cta` (modale), bouton « Passer à Pro » (`l10n.proUpgradeButton`, page de comparaison), tuile `compare_toggle_pro_only` (ligne des scénarios). Nommer chaque test « achat intégré actif → CTA vers /pro présent ».

- [ ] **Step 3: Vérifier qu'ils échouent**

Run: `flutter test test/widget/upsell_messages_store_test.dart test/widget/scenario_limit_modal_test.dart test/widget/scenario_comparison_page_test.dart test/widget/saved_scenarios_row_test.dart`
Expected: les cas « achat actif » échouent (texte neutre / CTA absent) ; tous les autres passent.

- [ ] **Step 4: Implémenter** — dans chaque fichier, ajouter `canOfferUpgrade` à l'import existant de `store_billing.dart` (ou remplacer `isStoreApp` s'il n'est plus utilisé dans le fichier) et :

```dart
// property_submit_error_l10n.dart (même forme pour tenants et leases)
      PropertySubmitError.limitReached => canOfferUpgrade
          ? l10n.propertiesErrorLimitReached
          : l10n.propertiesErrorLimitReachedStore,

// upload_file_error_reason_l10n.dart — commentaire mis à jour
      // Pas d'upsell « Passez à … » dans une app store sans achat intégré
      // (canOfferUpgrade), seulement la taille maximale.
      if (serverUpgradeToLevelId != null && canOfferUpgrade) {

// scenario_limit_reached_modal.dart
    final showUpgradeCta = !isAnonymous && canOfferUpgrade;

// scenario_comparison_page.dart
              if (canOfferUpgrade) ...[

// saved_scenarios_row.dart
      if (!canOfferUpgrade) return const SizedBox.shrink();
```

Mettre à jour les commentaires voisins qui disent « Apps iOS/Android : aucun CTA… » en « App store sans achat intégré ([canOfferUpgrade]) : … ».

- [ ] **Step 5: Vérifier que les tests passent, puis la suite entière**

Run:
```bash
flutter test test/widget/upsell_messages_store_test.dart test/widget/scenario_limit_modal_test.dart test/widget/scenario_comparison_page_test.dart test/widget/saved_scenarios_row_test.dart
dart format lib test
flutter analyze
flutter test
```
Expected: tout PASS ; « No issues found! ».

- [ ] **Step 6: Commit**

```bash
git add lib/features/properties/presentation/property_submit_error_l10n.dart lib/features/tenants/presentation/tenant_submit_error_l10n.dart lib/features/leases/presentation/lease_submit_error_l10n.dart lib/features/documents/presentation/upload_file_error_reason_l10n.dart lib/features/simulator/presentation/widgets/scenario_limit_reached_modal.dart lib/features/simulator/presentation/scenario_comparison_page.dart lib/features/simulator/presentation/widgets/saved_scenarios_row.dart test/widget/upsell_messages_store_test.dart test/widget/scenario_limit_modal_test.dart test/widget/scenario_comparison_page_test.dart test/widget/saved_scenarios_row_test.dart
git commit -m "feat(iap): textes d'incitation sur canOfferUpgrade (FEAT-044e lot 2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Documentation et état

**Files:**
- Modify: `docs/MOBILE.md` (nouvelle section après « Test Lab (Robo) »)
- Modify: `docs/STORE_COMPLIANCE.md`
- Modify: `dart-defines.prod.example.json`
- Modify: `docs/state/FEATURES.md` (ligne FEAT-044e), `docs/state/CHANGELOG.md` (entrée en tête de la période courante)

- [ ] **Step 1: `docs/MOBILE.md`** — ajouter :

```markdown
## Achat intégré (FEAT-044e)

Interrupteur `IAP_ENABLED` (défaut `false`) + clés SDK RevenueCat publiques
`REVENUECAT_APPLE_API_KEY` (`appl_…`) et `REVENUECAT_GOOGLE_API_KEY`
(`goog_…`), par dart-define, jamais committées. Coupé (ou clé absente) :
aucun appel au SDK, aucun achat, aucune incitation — comportement d'avant
FEAT-044e. Spec : `docs/superpowers/specs/2026-10-05-iap-revenuecat-mobile-design.md`.

- Code : `lib/core/config/store_billing.dart` (`isInAppPurchaseEnabled`,
  `canOfferUpgrade`), `lib/features/paid_plan/data/` (`StoreBillingService`,
  seule `RevenueCatStoreBillingService` importe `purchases_flutter`),
  `store_billing_session_sync.dart` (`logIn` pour un compte complet seulement,
  `logOut` en le quittant).
- **Ne pas activer avant le lot 3** (écran d'achat `/pro` en mode store) ni
  avant les produits App Store / Play et l'offre RevenueCat (checklist #207).
- Build d'essai, une fois prêt :

  ```bash
  flutter build ipa --release \
    --dart-define=APP_ENV=prod \
    --dart-define=IAP_ENABLED=true \
    --dart-define=REVENUECAT_APPLE_API_KEY=appl_xxx
  ```
```

- [ ] **Step 2: `docs/STORE_COMPLIANCE.md`** — à l'endroit qui décrit les textes d'incitation masqués dans les apps (chercher `isStoreApp`), préciser : « Prédicat unique `canOfferUpgrade` (`!isStoreApp || isInAppPurchaseEnabled`) : incitations masquées dans une app store tant que l'achat intégré est coupé, visibles quand il est actif (FEAT-044e). »

- [ ] **Step 3: `dart-defines.prod.example.json`** — remplacer par :

```json
{
  "APP_ENV": "prod",
  "IAP_ENABLED": "false",
  "REVENUECAT_APPLE_API_KEY": "",
  "REVENUECAT_GOOGLE_API_KEY": ""
}
```

- [ ] **Step 4: État** — `docs/state/FEATURES.md`, ligne FEAT-044e : remplacer « lots 2-3 app 📋 (pas de `purchases_flutter`) » par « lot 2 app (fondations : `purchases_flutter`, `IAP_ENABLED`, `StoreBillingService`, `canOfferUpgrade`) 🚧 branche `feat/044e-iap-app-foundations` ; lot 3 📋 ». `docs/state/CHANGELOG.md` : nouvelle entrée en tête `### FEAT-044e lot 2 : achat intégré, fondations de l'app (2026-10-09)` résumant les 4 tâches en 3-4 puces (interrupteur coupé par défaut, aucun effet visible).

- [ ] **Step 5: Commit**

```bash
git add docs/MOBILE.md docs/STORE_COMPLIANCE.md dart-defines.prod.example.json docs/state/FEATURES.md docs/state/CHANGELOG.md
git commit -m "docs(iap): achat intégré — interrupteur, clés, fondations (FEAT-044e lot 2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
