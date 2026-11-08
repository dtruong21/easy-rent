# Correctifs conformité stores (App Store / Google Play) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fermer les écarts de conformité stores trouvés par l'audit du 2026-09-30 avant la sortie des apps iOS/Android : aucun chemin de paiement Stripe dans les apps des stores, résiliation de l'abonnement Stripe à la suppression du compte, texte d'autorisation photos iOS, documentation à jour.

**Architecture:** Côté Flutter, un seul prédicat `isStoreApp` (iOS/Android hors web) masque tout parcours d'achat, de prix et de changement d'offre ; l'achat intégré (RevenueCat) viendra plus tard se brancher au même endroit. Côté Functions, `deleteAccount` résilie immédiatement les abonnements Stripe gérables de l'utilisateur AVANT toute purge ; la clé Stripe est choisie par l'Origin (web) ou, sans Origin (mobile), par la base du compte.

**Tech Stack:** Flutter/Riverpod/go_router/gen_l10n, Cloud Functions TS (firebase-functions v6, stripe SDK, vitest).

## Global Constraints

- Apps des stores (iOS/Android) : **aucun** bouton, lien ou prix menant à un achat hors achat intégré ; **aucune** mention d'un achat possible sur le site web (anti-steering Apple 3.1.1, Play Paiements).
- Web : comportement **strictement inchangé** (Stripe checkout, changement d'offre, résiliation, réactivation).
- `deleteAccount` : la résiliation Stripe se fait **avant** toute purge ; si elle échoue, rien n'est purgé et l'appel échoue en `internal` (l'utilisateur peut relancer).
- Clé Stripe : Origin présent → `resolveStripeKeyOrThrow` existant (inchangé). Origin absent ou vide (mobile) → base du compte : `staging` → clé TEST, `(default)` → clé LIVE.
- Émulateur Functions (`process.env.FUNCTIONS_EMULATOR === "true"`) : la résiliation Stripe est sautée (log), pour ne pas bloquer les suppressions locales.
- Aucune donnée ni identifiant Stripe fourni par le client ; recherche par metadata `rc_app_user_id` = uid (comme `manageSubscription`).
- l10n : toute nouvelle chaîne en FR (`app_fr.arb`) **et** EN (`app_en.arb`, template, avec `description`).
- Flutter : `export PATH=/opt/homebrew/bin:$PATH` ; `dart format` sur les fichiers touchés ; `flutter analyze` sans issue ; `flutter test` vert. Ne jamais committer `*.freezed.dart` / `*.g.dart`.
- Functions : `npm run lint`, `npm run build`, `npm test` dans `functions/` (Node 22 : `export PATH=/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:$PATH`) ; `bash scripts/check-db-isolation.sh` vert.
- Commits : `git add` chemins explicites, jamais `-A` ; ne jamais ajouter `firebase.altports.local.json`. Fin de message : `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Aucun déploiement.

---

### Task 1: Flutter — aucun achat hors store dans les apps iOS/Android

**Files:**
- Create: `lib/core/config/store_billing.dart`
- Create: `test/flutter_test_config.dart`
- Modify: `lib/features/paid_plan/presentation/pro_pricing_page.dart`, `lib/features/paid_plan/presentation/widgets/subscription_section.dart`, `lib/features/profile/presentation/profile_page.dart` (bannière Pro), `lib/features/simulator/presentation/widgets/scenario_limit_reached_modal.dart`, `lib/features/simulator/presentation/scenario_comparison_page.dart`, `lib/features/simulator/presentation/widgets/saved_scenarios_row.dart`, `lib/features/paid_plan/presentation/pro_cancel_page.dart`, `lib/features/profile/presentation/delete_account_page.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`, `ios/Runner/Info.plist`
- Test: `test/unit/store_billing_test.dart` + widget tests existants/nouveaux des écrans touchés

**Interfaces:**
- Produces: `bool get isStoreApp` et `@visibleForTesting bool? debugIsStoreAppOverride` dans `lib/core/config/store_billing.dart`.

- [ ] **Step 1: Prédicat `isStoreApp`**

```dart
// lib/core/config/store_billing.dart
import 'package:flutter/foundation.dart';

/// Vrai dans les apps iOS/Android distribuées par l'App Store et Google Play.
/// Tout achat numérique doit y passer par l'achat intégré du store (App Store
/// 3.1.1, règle Paiements de Google Play) : Stripe, les prix et le changement
/// d'offre n'y sont jamais proposés. Le web garde le parcours Stripe.
bool get isStoreApp =>
    debugIsStoreAppOverride ??
    (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android));

/// Forçage pour les tests (flutter_test simule Android par défaut).
@visibleForTesting
bool? debugIsStoreAppOverride;
```

`test/flutter_test_config.dart` force `debugIsStoreAppOverride = false` (comportement web) pour toute la suite, afin que les tests existants du parcours Stripe restent valides :

```dart
import 'dart:async';

import 'package:easy_rent/core/config/store_billing.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugIsStoreAppOverride = false;
  await testMain();
}
```

(Vérifier le nom du package dans `pubspec.yaml` pour l'import.) Les nouveaux tests « app store » posent `debugIsStoreAppOverride = true` et le remettent à `false` en `tearDown`.

Test unitaire `test/unit/store_billing_test.dart` : override `true` → `isStoreApp` vrai ; override `false` → faux ; override `null` + `debugDefaultTargetPlatformOverride = TargetPlatform.iOS` → vrai, `TargetPlatform.macOS` → faux (remettre les deux overrides à leur valeur d'origine en `tearDown`).

- [ ] **Step 2: Comportement quand `isStoreApp` est vrai**

1. **`ProPricingPage` (`/pro`)** : ni cartes d'offres, ni prix, ni bascule mensuel/annuel, ni bouton. À la place, un message neutre (clé `proStoreAppUnavailable`) :
   - FR : « Les offres payantes ne sont pas encore proposées dans l'application. »
   - EN : "Paid plans aren't available in the app yet."
   Aucune mention du site web.
2. **Points d'entrée vers `/pro`** masqués : bannière « Passer à Pro » du profil, bouton « Changer d'offre » de `SubscriptionSection`, CTA « Passer à … » de `ScenarioLimitReachedModal` (la modale garde son message et un bouton de fermeture), CTA de `ScenarioComparisonPage`, tuile de `SavedScenariosRow`, bouton vers `/pro` de `ProCancelPage`.
3. **`SubscriptionSection`** pour un abonnement web (Stripe) : statut + **résiliation** conservés ; **réactivation** masquée (reprendre une facturation hors store = achat). Abonnement via store (`proStore` ∈ {`app_store`, `play_store`}) : inchangé.
4. **Textes des modales de limite** : vérifier qu'aucun prix n'y figure ; sinon, ne pas l'afficher quand `isStoreApp`.

Web (`isStoreApp` faux) : tout reste identique — les tests existants le garantissent.

- [ ] **Step 3: Avertissement abonnement à la suppression du compte (toutes plateformes)**

Dans `delete_account_page.dart`, lire l'abonnement courant (même source que `SubscriptionSection` : `proStore`, palier) et afficher, avant la confirmation :
- abonnement via store (`app_store`/`play_store`), clé `deleteAccountStoreSubscriptionWarning` :
  - FR : « La suppression du compte ne résilie pas un abonnement souscrit via l'App Store ou Google Play. Résiliez-le dans les réglages de votre store pour arrêter la facturation. »
  - EN : "Deleting your account doesn't cancel a subscription bought through the App Store or Google Play. Cancel it in your store settings to stop billing."
- abonnement web (Stripe, palier payant et `proStore` absent ou `stripe`), clé `deleteAccountWebSubscriptionNotice` :
  - FR : « Votre abonnement Baillan est résilié immédiatement, sans remboursement de la période en cours. »
  - EN : "Your Baillan subscription is canceled immediately, with no refund for the current period."
- palier gratuit : rien.

- [ ] **Step 4: iOS `Info.plist`**

Ajouter, après `ITSAppUsesNonExemptEncryption` :

```xml
	<!-- file_picker embarque du code d'accès aux photos : sans texte
	     d'explication, l'envoi App Store Connect peut être refusé
	     (ITMS-90683), même si l'app n'ouvre que le sélecteur de fichiers. -->
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Baillan accède à vos photos uniquement quand vous choisissez d'ajouter un document ou un justificatif.</string>
```

- [ ] **Step 5: Tests (TDD)**

Pour chaque écran touché, un test widget avec `debugIsStoreAppOverride = true` qui prouve l'absence du CTA/prix (clés `Key` existantes, ex. `btn_plan_subscribe_pro`, `btn_subscription_change_plan`, `scenario_limit_upgrade_cta`), et l'affichage de `proStoreAppUnavailable` sur `/pro`. Tests de `delete_account_page` pour les 3 cas (store / web / gratuit). Les tests existants (web) restent verts sans modification.

- [ ] **Step 6: Vérifier et committer**

`flutter gen-l10n` si nécessaire, `dart format` des fichiers touchés, `flutter analyze`, `flutter test`. Puis :

```bash
git add <fichiers touchés, chemins explicites>
git commit -m "fix(stores): aucun achat hors store dans les apps iOS/Android"
```

---

### Task 2: Functions — `deleteAccount` résilie l'abonnement Stripe

**Files:**
- Modify: `functions/src/utils/stripe_env.ts` (nouveau helper pur)
- Modify: `functions/src/callable/manage_subscription.ts` (exporter la sélection des abonnements gérables si utile)
- Modify: `functions/src/callable/delete_account.ts`
- Test: `functions/src/__tests__/stripe_env.test.ts` (créer ou compléter), `functions/src/__tests__/delete_account.test.ts`

**Interfaces:**
- Produces: `export function resolveStripeKeyForRequest(origin: unknown, isStagingDb: boolean, liveKey: string, testKey: string): string` dans `stripe_env.ts`.

- [ ] **Step 1: Helper pur de choix de clé (TDD)**

`resolveStripeKeyForRequest(origin, isStagingDb, liveKey, testKey)` :
- `origin` chaîne non vide → `resolveStripeKeyOrThrow(origin, liveKey, testKey)` (inchangé, y compris l'erreur `origin_not_allowed`) ;
- sinon (mobile) → `isStagingDb ? testKey : liveKey`.

Tests : Origin prod → live ; Origin staging → test ; Origin localhost → test ; Origin inattendu → throw `origin_not_allowed` ; sans Origin + base staging → test ; sans Origin + base prod → live ; Origin `""` traité comme absent.

- [ ] **Step 2: Résiliation dans `deleteAccount` (TDD)**

- `onCall` options : ajouter `secrets: [stripeSecret, stripeTestSecret]` (mêmes `defineSecret("STRIPE_SECRET_KEY")` / `"STRIPE_SECRET_KEY_TEST"` que `manage_subscription.ts`), garder `region` et `timeoutSeconds`.
- Après `assertRecentAuthForNonAnonymousAccount` et `const db = await dbForRequest(request)`, **avant** l'étape (a) :
  - si `process.env.FUNCTIONS_EMULATOR === "true"` → `logger.info` et on saute ;
  - sinon : clé = `resolveStripeKeyForRequest(origin, db.databaseId === "staging", …)` ; recherche `stripe.subscriptions.search({query: \`metadata['rc_app_user_id']:'${uid}'\`, limit: 20})` (réutiliser `RC_APP_USER_ID_METADATA_KEY`) ; pour chaque abonnement au statut ∈ {active, trialing, past_due, unpaid} → `stripe.subscriptions.cancel(id)` (effet immédiat) ; `logger.info` du nombre résilié (uid seulement).
  - toute erreur Stripe → `logger.error` + `throw new HttpsError("internal", "subscription cancel failed — retry")`, **avant** la moindre purge. `origin_not_allowed` reste un `failed-precondition` (HttpsError relancée telle quelle).
- Mettre à jour le docblock (nouvelle étape « (0) résiliation Stripe »).

Tests (`vi.mock("stripe", …)` : fausse classe exposant `subscriptions.search` et `subscriptions.cancel`, capture de la clé passée au constructeur) :
1. web prod (Origin `https://app.baillan.com`), un abonnement `active` + un `canceled` → seul l'`active` est résilié, clé LIVE, purge effectuée ;
2. mobile (sans Origin), compte en base staging (doc landlord seulement dans la fausse base staging) → clé TEST ;
3. aucun abonnement → aucun `cancel`, purge effectuée ;
4. `cancel` qui échoue → `internal`, **rien n'est purgé** (doc landlord toujours présent) ;
5. `FUNCTIONS_EMULATOR=true` → aucun appel Stripe, purge effectuée (restaurer la variable après le test).
Les tests existants de `delete_account.test.ts` restent verts (ajouter un Origin prod ou le mock Stripe par défaut « aucun abonnement » selon le harnais).

- [ ] **Step 3: Vérifier et committer**

`npm run lint`, `npm run build`, `npm test` (dans `functions/`), `bash scripts/check-db-isolation.sh`. Puis :

```bash
git add functions/src/utils/stripe_env.ts functions/src/callable/delete_account.ts <autres fichiers touchés>
git commit -m "fix(account): la suppression du compte résilie l'abonnement Stripe"
```

---

### Task 3: Documentation — audit stores du 2026-09-30

**Files:**
- Modify: `docs/STORE_COMPLIANCE.md`, `docs/state/CHANGELOG.md`, shard `docs/state/functions/account.md` (description de `deleteAccount`)

- [ ] **Step 1: `docs/STORE_COMPLIANCE.md`**

Ajouter en tête une section « Ré-audit du 2026-09-30 » :
- vérifié sur l'APK : `targetSdk 36` / `compileSdk 36` (exigence Play du 31/08/2026 remplie), alignement 16 Ko OK (toutes les `.so` arm64 à ≥ 0x4000, `zipalign -P 16` OK), permissions (INTERNET, ACCESS_NETWORK_STATE, WAKE_LOCK, `c2dm.RECEIVE` et `READ_GSERVICES` tirées par Firebase) ;
- iOS : cible **iOS 15** (et non 13), build Xcode 27 ;
- abonnement Pro : paiement Stripe **web uniquement**, masqué dans les apps (`isStoreApp`) ; décision du 2026-09-30 : **achat intégré (RevenueCat) avant la sortie des apps**, et règle 3.1.3(b) (un abonnement web qui débloque l'app iOS doit aussi être achetable en achat intégré) ;
- suppression de compte : résiliation Stripe immédiate + avertissement pour les abonnements store ;
- `NSPhotoLibraryUsageDescription` ajouté (ITMS-90683) ;
- bloquant restant : mentions légales en brouillon dans l'app (règle 2.1, contenu provisoire).
Corriger les lignes périmées (« V1 gratuite sans IAP », « Deployment target iOS 13 », « Xcode 26.6 »).

- [ ] **Step 2: État projet**

`docs/state/CHANGELOG.md` : entrée « FIX conformité stores (2026-09-30) » (3 lignes). Shard functions `account` : `deleteAccount` résilie les abonnements Stripe gérables avant la purge (clé par Origin, sinon par base du compte ; sauté sous émulateur). **Redéploiement des Functions requis.**

- [ ] **Step 3: Commit**

```bash
git add docs/STORE_COMPLIANCE.md docs/state/CHANGELOG.md docs/state/functions/account.md
git commit -m "docs: ré-audit conformité stores du 2026-09-30"
```
