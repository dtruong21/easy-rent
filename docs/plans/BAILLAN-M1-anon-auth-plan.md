# Plan — BAILLAN-M1 : Anonymous auth + subscription tier + expiration + linkWithCredential

## Corrections au brief

Après lecture du code, deux ajustements factuels vs le brief :

1. La collection Firestore existante s'appelle **`investment_scenarios`** (pas `simulation_scenarios`). On garde le nom existant — pas de rename.
2. Il y a **15** fakes `AuthRepository` dans `test/` (pas 13+). Tous devront gagner les no-ops.
3. `login_controller.dart` **ne fait pas** de `context.go` explicite post-login : il s'appuie exclusivement sur `GoRouterRefreshStream` + la garde. La redirection vers `/dashboard` sera donc portée par la garde router (`redirect` callback), pas par les controllers.

Le reste du brief est correct et locked.

## Summary

Introduire Firebase Anonymous Auth comme rampe d'onboarding vers le simulateur, tout en préservant l'invariant RGPD "consent horodaté au moment du signup". Trois états de session (`unauthenticated` / `anonymous` / `fullyAuthenticated`) pilotent le router (nouvelle landing publique en `/`, dashboard déplacé en `/dashboard`, simulateur ouvert aux anons). Un tier d'abonnement (`anonymous`/`free`/`paid`) porté par `landlords/{uid}` gate côté client le nombre de scénarios sauvegardables. Les comptes anons expirent après 14 jours glissants d'inactivité, purgés par un cron Cloud Scheduler. Trois nouvelles méthodes `linkAnonymousWith*` explicites permettent l'upgrade anon → compte réel en préservant l'UID et les scénarios déjà sauvés ; une callable `finalizeAnonymousUpgrade` stamp le consent RGPD serveur-side après le `linkWithCredential`.

## Data model changes

### `landlords/{uid}` — nouveaux champs

| Champ | Type | Défaut | Notes |
|---|---|---|---|
| `isAnonymous` | `bool` | `false` | `true` pour un anon, repassé à `false` au finalize upgrade. |
| `subscriptionTier` | `string` enum | `'free'` | `'anonymous'` \| `'free'` \| `'paid'`. |
| `anonExpiresAt` | `Timestamp?` | `null` | Seulement set si `isAnonymous==true`. Renewed sur activité. |
| `rgpdConsentAt` | `Timestamp?` | `null` | **Devient nullable** — un anon N'A PAS de consent. Existant : `NOT NULL`, à assouplir. |
| `rgpdConsentVersion` | `string?` | `null` | Idem, nullable. |
| `email` | `string?` | `null` | Devient nullable (un anon n'a pas d'email). |
| `fullName` | `string` | `''` | Chaîne vide autorisée pour anon (rule à relaxer). |

### Nouvelle collection `paid_plan_interest/{uid}`

```
{
  id: uid,
  landlordId: uid,
  features: ['comparateur','sensibilite','fiscal_lmnp','export_pdf'],  // sous-ensemble
  email: string?,      // contact opt-in (peut différer de landlord.email)
  notifyAt: Timestamp, // set côté serveur au create
  updatedAt: Timestamp
}
```

DocId = `uid` du landlord (1:1). Écrit uniquement par le landlord lui-même.

### `investment_scenarios/{id}`

Aucun changement de schéma. On documente que les scénarios créés par un anon ont `landlordId = anonUid` et seront supprimés par le cron `cleanupExpiredAnon` en cascade.

## Firestore rules

Modifications à `firestore.rules` :

```
function isAnonymous() {
  return isSignedIn()
    && request.auth.token.firebase.sign_in_provider == 'anonymous';
}

function isFullyAuthed() {
  return isSignedIn() && !isAnonymous();
}
```

### `landlords/{uid}`

- `create` : deux branches acceptées.
  - **Anon** (`isAnonymous() && request.auth.uid == uid`) : `id == uid`, `isAnonymous == true`, `subscriptionTier == 'anonymous'`, `anonExpiresAt is timestamp`, `rgpdConsentAt == null`, `rgpdConsentVersion == null`, `fullName == ''`, `email == null`, `deletedAt == null`.
  - **Fully-authed** (comportement actuel) : `isFullyAuthed()`, avec `rgpdConsentAt/Version` obligatoires et `subscriptionTier == 'free'`, `isAnonymous == false`, `anonExpiresAt == null`.
- `update` : conservation `preservesImmutables`, `id`, `rgpdConsentAt`, `rgpdConsentVersion` immuables. L'anon PEUT toucher `anonExpiresAt` (renewal) et `updatedAt`. **Interdit** à l'anon : toucher `subscriptionTier` (seul le serveur via finalize le passe à `'free'`), toucher `isAnonymous`. Le finalize passe par admin SDK donc bypass rules — pas de gate côté client sur ces champs.

### Toutes les collections métier (`properties`, `tenants`, `leases`, `payments`, `receipts`, `documents`)

Ajouter `isFullyAuthed()` en garde sur `create` (`list`/`get` restent gated par ownership, ce qui suffit à empêcher l'anon de lire — il n'a pas de rows). Les `create/update/delete` déjà en `if false` (leases, payments, receipts, documents) sont naturellement gated via la callable qui doit vérifier `context.auth.token.firebase.sign_in_provider != 'anonymous'` côté serveur également (defense-in-depth).

Concrètement : `properties`/`tenants` ont un `create` direct ; ajouter `&& isFullyAuthed()` à leur `allow create`.

### `investment_scenarios/{id}`

- `create` : `isSignedIn()` (accepte anon). Aucun changement fonctionnel — l'anon peut créer/mettre à jour ses scénarios. Le count est enforcé côté client, PAS dans les rules (assumé dans le brief).
- Ajouter défense simple : `request.resource.data.landlordId == request.auth.uid` (déjà présent).

### `paid_plan_interest/{uid}`

```
match /paid_plan_interest/{uid} {
  allow get: if isOwner(uid);
  allow list: if false;
  allow create, update: if isFullyAuthed()  // pas d'anon dans cette collection
    && request.auth.uid == uid
    && request.resource.data.landlordId == uid
    && request.resource.data.features is list
    && request.resource.data.features.size() > 0
    && request.resource.data.features.size() <= 10;
  allow delete: if false;
}
```

## Cloud Functions

### `functions/src/auth/handle_new_user.ts` — refactor

Branche sur `event.data.providerData` / `event.data.email` :

- Si aucun provider data OU sign-in provider anonyme :
  - N'écrit PAS `rgpdConsentAt/Version` (null).
  - Écrit `isAnonymous: true`, `subscriptionTier: 'anonymous'`, `anonExpiresAt: now + 14 days`, `email: null`, `fullName: ''`.
- Sinon : comportement actuel + ajoute `isAnonymous: false`, `subscriptionTier: 'free'`, `anonExpiresAt: null`.

Note technique : `beforeUserCreated` n'expose pas de flag "isAnonymous" direct — heuristique = `!event.data.email && (!event.data.providerData || event.data.providerData.length === 0)`. Confirmer dans Cloud Function logs après un premier essai staging.

### `functions/src/callable/finalize_anonymous_upgrade.ts` — NOUVEAU (callable)

**Contrat** :
```
input:  { rgpdConsent: boolean, rgpdConsentVersion: string }
output: { ok: true, tier: 'free' }
```

Logique (admin SDK, bypass rules) :

1. Vérifie `context.auth != null` et `context.auth.token.firebase.sign_in_provider != 'anonymous'` (le client vient de `linkWithCredential`, donc le provider a changé — c'est notre signal de succès).
2. Si `rgpdConsent !== true` → `HttpsError('failed-precondition', 'rgpd-consent-required')` + delete du user Auth (rollback strict — cohérent avec `signUpWithGoogle`).
3. `landlords/{uid}.update({ isAnonymous: false, subscriptionTier: 'free', anonExpiresAt: null, rgpdConsentAt: now, rgpdConsentVersion: <version>, email: token.email, fullName: token.name ?? '', updatedAt: now, upgradedFromAnonAt: now, signupProvider: <provider> })`.
4. Log l'événement pour audit RGPD.

**Pourquoi callable et pas trigger** : préférence explicite du brief. Le trigger `onIdTokenChanged` n'existe pas en v2 admin SDK, et un `onUserUpdate` Firestore ne verrait pas le passage anon → non-anon (le doc landlord n'a pas encore été touché). La callable donne un point de synchronisation prévisible + retry natif.

### `functions/src/scheduled/cleanup_expired_anon.ts` — NOUVEAU (cron)

```typescript
export const cleanupExpiredAnon = onSchedule({
  schedule: 'every day 03:00',
  timeZone: 'Europe/Paris',
  region: 'europe-west1',
  timeoutSeconds: 540,
  memory: '512MiB',
}, async () => { ... });
```

Étapes :

1. Query `landlords` where `isAnonymous == true` and `anonExpiresAt <= now`. Limit 100.
2. Pour chaque batch :
   - Query et delete `investment_scenarios` where `landlordId == uid` (hard delete, pas soft — l'anon n'a pas de valeur légale).
   - Delete `paid_plan_interest/{uid}` si existe.
   - Delete `landlords/{uid}`.
   - `admin.auth().deleteUser(uid)`.
3. Logger nb utilisateurs purgés, erreurs individuelles catch (continue-on-error par uid).

Idempotent : si une purge partielle échoue en cours de route, le run suivant reprend le reste.

## Flutter changes

### Domain / Session

- **`lib/features/auth/domain/session_state.dart`** — enum + freezed :
  ```dart
  enum SessionState { unauthenticated, anonymous, fullyAuthenticated }
  ```

### Providers

- **`lib/features/auth/application/auth_session_provider.dart`** — refactor :
  - Garder `authStateChangesProvider` (source).
  - Nouveau `sessionStateProvider: Provider<SessionState>`. Logique :
    - `user == null` → `unauthenticated`
    - `user.isAnonymous == true` → `anonymous`
    - `user.emailVerified == true && !user.isAnonymous` → `fullyAuthenticated`
    - `user != null && !emailVerified && !isAnonymous` → `unauthenticated` (comme aujourd'hui).
  - Deprecated : garder `isAuthenticatedProvider` = `sessionStateProvider == fullyAuthenticated` en shim (retro-compat des call-sites qui l'utilisent encore ; migration progressive).

### AuthRepository

- **`lib/features/auth/data/auth_repository.dart`** — nouvelles méthodes (préférence brief = **explicites**, pas magiques) :
  - `Future<void> signInAnonymously()` — appelle `_auth.signInAnonymously()`. Le CF `handleNewUser` provisionne le doc anon.
  - `Future<void> linkAnonymousWithEmailPassword({ required String email, required String password, required String fullName, required bool rgpdConsent })` — EmailAuthProvider.credential → `currentUser.linkWithCredential` → `updateDisplayName(fullName)` → callable `finalizeAnonymousUpgrade(rgpdConsent, rgpdConsentVersion)` → `sendEmailVerification` → `signOut` (cohérent avec `signUpWithPassword`).
  - `Future<void> linkAnonymousWithGoogle({ required bool rgpdConsent })` — GoogleAuthProvider popup → `currentUser.linkWithPopup(provider)` → callable finalize.
  - `Future<void> linkAnonymousWithApple({ required bool rgpdConsent })` — idem Apple.

Les `signUpWith*` existantes ne détectent PAS `isAnonymous` — décision explicite pour éviter les bugs (préférence du brief). Les screens de signup vérifient `currentUser?.isAnonymous == true` et appellent la variante `linkAnonymousWith*` ou `signUpWith*` selon le cas.

### PaidPlanInterest

- **`lib/features/paid_plan/domain/paid_plan_interest.dart`** — freezed model (`features`, `email?`, `notifyAt`).
- **`lib/features/paid_plan/data/paid_plan_interest_repository.dart`** — interface + Firestore impl : `Future<void> markInterest({List<String> features, String? email})`.
- **`lib/features/paid_plan/application/paid_plan_interest_controller.dart`** — AsyncNotifier pour le CTA.

### Router (3-état)

Fichier `lib/core/router/app_router.dart` — refonte du callback `redirect` :

```
publicRoutes = { '/', '/login', '/signup', '/forgot-password', '/reset-password', '/privacy' }
anonAccessible = publicRoutes ∪ { '/simulator', '/simulator/:id' }

switch (sessionState):
  case unauthenticated:
    if (location in publicRoutes) return null;
    return '/login';
  case anonymous:
    if (location == '/') return '/simulator';
    if (location in anonAccessible) return null;
    return '/' /* + queryParam gated=true pour message */;
  case fullyAuthenticated:
    if (location == '/') return '/dashboard';
    if (location in { '/login', '/signup' }) return '/dashboard';
    return null;
```

**Route swap** : `/` → `LandingPage` (nouvelle), `/dashboard` → `DashboardPage` (existant). Nouvelle route `GoRoute('/dashboard', ...)` ; le `/` existant devient LandingPage.

### Landing

- **`lib/features/landing/presentation/landing_page.dart`** — nouvelle, publique.
- **`lib/features/landing/presentation/widgets/landing_hero.dart`** — wordmark "Baillan.", tagline Cochin italic, 2 CTAs égaux ("Continuer sans compte" → `signInAnonymously()` puis go `/simulator` ; "Créer un compte" → `/signup`) + lien "J'ai déjà un compte" → `/login`. Style repris de `login_page.dart`.

### Simulator

- **`lib/features/simulator/application/scenario_limit_controller.dart`** — expose `scenarioCountProvider` (Stream on `investment_scenarios` where `landlordId == uid && deletedAt == null` avec `.snapshots()` pour comptage live). `scenarioLimitForTierProvider` = 1/3/`double.infinity`. `canSaveAnotherProvider` = derived boolean.
- **`lib/features/simulator/presentation/widgets/tier_chip.dart`** — chip Cochin italic + caps tracked. Affiche count live pour le tier free.
- **`lib/features/simulator/presentation/widgets/scenario_limit_reached_modal.dart`** — modal FR formel. Deux modes : `anonymous` (CTA "Créer un compte") et `free` (CTA "M'avertir du lancement" du plan pro → écrit `paid_plan_interest`).
- **`lib/features/simulator/presentation/widgets/coming_soon_paid_plan_section.dart`** — section pied. Uniquement pour tier `free`. 4 features + bouton "M'avertir du lancement". `anonymous` voit à la place un panneau "Créer un compte gratuit d'abord".
- **`lib/features/simulator/presentation/simulator_page.dart`** — insertion chip en haut + section pied conditionnelle. `_onSaveScenario` : vérifie `canSaveAnotherProvider` avant `create()` ; si `false` → `showScenarioLimitReachedModal(tier)`.

### AnonDemoBanner

- **`lib/features/auth/presentation/widgets/anon_demo_banner.dart`** — bandeau persistant (papier/olive). Visible sur landing, /simulator, /privacy quand `sessionState == anonymous`. Texte évolutif selon `daysLeft`:
  - `>3` : "Mode démo — 1 scénario · [Créer un compte pour tout débloquer]"
  - `≤3 && >1` : "Mode démo — expire dans {n} jours · [Créer un compte pour tout garder]"
  - `≤1` : modal bloquante à l'ouverture (`_showAnonExpiryImminentModal`) — pas juste bandeau.

Wiring via `Scaffold` wrapper dans les pages concernées, ou via `ShellRoute` GoRouter pour l'appliquer à un sous-graphe (préférence : wrapper explicite par page — plus simple, testable).

### Activité renewal

- **`lib/features/auth/application/anon_expiry_renewer.dart`** — Notifier. Au boot app (si `sessionState == anonymous`) et au save scénario, `update({ anonExpiresAt: now + 14d })`. Debounce 1×/heure max pour éviter le spam d'écritures (throttled via un `DateTime? _lastRenewed` mémoire).

## Routes ajoutées / modifiées

| Route | Avant | Après | Session state autorisée |
|---|---|---|---|
| `/` | `DashboardPage` | `LandingPage` | publique (redirect selon état) |
| `/dashboard` | (n'existait pas) | `DashboardPage` | `fullyAuthenticated` |
| `/simulator` | `fullyAuthed` seul | ouvert | `anonymous` + `fullyAuthenticated` |
| `/simulator/:id` | idem | idem | idem |
| `/login`, `/signup`, `/forgot-password`, `/reset-password`, `/privacy` | publique | publique | tous |
| Toutes les autres | `fullyAuthed` seul | inchangé | `fullyAuthenticated` |

## Tests plan

Voir `tests_plan` de l'output structuré. Minimum 6 tests unit+widget + mise à jour des 15 fakes AuthRepository (ajouter no-op pour `signInAnonymously` + 3 méthodes `linkAnonymousWith*`).

## Ordre d'exécution recommandé

1. **Backend** : rules + `handle_new_user` refactor + callable `finalizeAnonymousUpgrade` + cron `cleanupExpiredAnon` (déployable en solo, testable via emulator).
2. **Domain** : `session_state.dart` + `sessionStateProvider`.
3. **Repo** : `signInAnonymously` + 3 `linkAnonymousWith*` + màj des 15 fakes.
4. **Router** : refonte 3-état + route `/dashboard`.
5. **Landing** : `LandingPage` + hero + CTAs.
6. **Simulator** : tier chip, limit controller, modal, coming soon section, banner.
7. **Paid plan interest** : model + repo + CTA "M'avertir".
8. **Tests** : suite complète + màj tests existants (routing).
9. **QA manuelle** : anon → simulator, save 1 scénario → modal, signup depuis anon → scénarios préservés, expiration 14 jours (mock timestamp).

## Risques

- **Migration `rgpdConsentAt` nullable** : impacts sur reads existants qui font `data['rgpdConsentAt'].toDate()` — auditer les 3-4 usages.
- **Callable finalize peut échouer après linkWithCredential réussi** : le user est déjà lié côté Auth. Client doit retry ou afficher un état "à finaliser" (bouton "Réessayer" qui rappelle la callable). Ne PAS deleteUser en cas de retry — irréversible.
- **`beforeUserCreated` et anonymous** : à confirmer que Identity Platform déclenche bien le trigger pour `signInAnonymously`. Fallback : trigger `onCreate` Firestore côté client via `set` idempotent.
- **Coût cron** : quotidien à 100 users max par run — à surveiller si l'app grossit (200 anons/jour actifs = purge lente). Escalade : passer à `every 6 hours` ou augmenter la limit.
- **Deux onglets même browser** : Firebase Auth partage l'état IndexedDB entre onglets. Un signInAnonymously dans onglet A est visible dans onglet B. Un signup dans B upgrade l'UID → A voit maintenant un user non-anon (via `authStateChanges`) et le router refresh redirige vers `/dashboard`. Comportement attendu.
- **localStorage cleared** : la session anon est perdue, le UID est effectivement zombie côté Firestore jusqu'au cron. Pas de risque de leak (données invisibles), juste du bruit à purger.
- **Regression email verification** : `sessionStateProvider` doit toujours refuser `emailVerified == false && !isAnonymous`. Sans ça, un user email non vérifié entrerait comme `fullyAuthenticated`.
- **Wording FR** : à valider avec product-owner (charte "papier/encre/olive/Cochin").
