# Onboarding jusqu'à la 1re quittance — Design

> **Statut** : Design validé (brainstorm 2026-09-15). Prêt pour `writing-plans`.
> **Domaine** : dashboard (checklist « Premiers pas ») + lecture transverse (properties, tenants, leases, payments, receipts).
> **Dépend de** : FEAT-006 (paiements) ✅, FEAT-007 (quittances) ✅, checklist onboarding existante ✅.

## Problème

La checklist d'onboarding « Premiers pas » (`OnboardingFirstSteps`) a deux défauts qui la font manquer son but — amener un nouveau bailleur jusqu'au moment de valeur :

1. **Elle disparaît trop tôt.** `DashboardRepository.isLandlordOnboarding()` renvoie `true` uniquement quand le compte a **zéro** bien **ET** zéro locataire **ET** zéro bail (`results.every((qs) => qs.docs.isEmpty)`, `dashboard_repository.dart:352-377`). Dès la création du **1er bien**, la condition bascule à `false` et toute la carte est remplacée par les KPI (vides à ce stade). Le bailleur perd le guide pour les étapes locataire et bail.
2. **Elle s'arrête avant l'aha.** Les 3 étapes statiques s'arrêtent à la création du bail (`onboarding_first_steps.dart`, `StatelessWidget` sans état, sans coche). Elle ne conduit jamais au **moment de valeur** : encaisser un loyer puis **générer la 1re quittance** — la sortie signature du produit (loi 6 juillet 1989).

## Décisions (validées 2026-09-14/15)

- **A — Fin de l'onboarding = 1re quittance générée.** L'existence d'au moins un document `receipts` marque l'aha atteint ; la checklist disparaît alors au profit du dashboard normal.
- **B — 5 étapes séparées** : bien → locataire → bail → enregistrer un paiement → générer une quittance (le paiement précède techniquement la quittance).
- **C — La checklist reste l'élément principal** du dashboard tant que l'onboarding n'est pas terminé (les KPI n'ont aucun sens avant le 1er bail/paiement).

## Périmètre

### Inclus

- Checklist **progressive et à état** : 5 étapes, chacune **cochée** quand son signal de données est présent. L'état est **dérivé des collections existantes** (aucune écriture, aucun nouveau champ Firestore) via des requêtes `limit(1)`.
- Reste affichée tant qu'aucune quittance n'existe (décision A) ; navigation vers la page de chaque étape.
- **Dismiss local** (« Passer ») persisté en `SharedPreferences` (patron `chartPeriodProvider`) — garde-fou pour ne jamais harceler un compte qui aurait des données mais pas de quittance (ex. bailleur établi qui partage ses PDF autrement). Zéro backend.
- i18n FR/EN.

### Exclus (YAGNI)

- Aucun nouveau champ/collection Firestore ; pas de suivi serveur de progression.
- Pas d'animation de célébration à la complétion (la bascule vers le dashboard normal suffit) — éventuelle V2.
- Pas de ré-ouverture de la checklist après dismiss (le lien local suffit ; un reset se fait en vidant les prefs).
- Pas de modification des pages de création/paiement/quittance elles-mêmes.

## Composants

### 1. Modèle de progression — `lib/features/dashboard/domain/onboarding_progress.dart`

`OnboardingProgress` (freezed) :

- `hasProperty`, `hasTenant`, `hasLease`, `hasPayment`, `hasReceipt` : `bool`.
- `firstLeaseId` : `String?` — l'id d'un bail existant (pour router les étapes 4-5, lease-scoped). `null` tant qu'aucun bail.
- Getter dérivé `isComplete => hasReceipt` (décision A).
- Getter `completedCount` (0-5) pour l'affichage « X/5 ».

### 2. Lecture — `DashboardRepository`

Remplacer `isLandlordOnboarding(): Future<bool>` par `fetchOnboardingProgress(): Future<OnboardingProgress>`.

- Requêtes **parallèles** `Future.wait` (patron existant) : `properties`, `tenants`, `leases`, `payments` (filtrées `landlordId == uid` + `deletedAt == null`, `limit(1)`), et `receipts` (`landlordId == uid`, `limit(1)` — un receipt compte même s'il est ensuite `isVoided` : l'aha, c'est de l'avoir généré ; confirmer à l'implémentation qu'aucun filtre soft-delete n'est requis sur `receipts`, collection immuable read-only).
- Pour `leases`, récupérer aussi l'`id` du doc retourné → `firstLeaseId`.
- `hasX = qs.docs.isNotEmpty`.

> Un seul aller-retour logique (5 requêtes parallèles, chacune `limit(1)` — coût minime, équivalent à l'ancienne fonction qui en faisait déjà 3).

### 3. Provider — `dashboard_provider.dart`

- `dashboardProvider` appelle `fetchOnboardingProgress()`.
- **`showOnboarding` = `!progress.isComplete && !dismissed`** (`dismissed` = provider de prefs, cf. composant 5).
- Si `showOnboarding` : court-circuiter les requêtes KPI (comme aujourd'hui pour l'onboarding) et exposer la progression au dashboard.
- Sinon : calcul KPI normal.
- `DashboardSnapshot` porte soit la progression (mode onboarding), soit les KPI — adapter le modèle (ex. champ `OnboardingProgress? onboarding` non-null en mode onboarding, `isOnboarding` conservé/dérivé).

### 4. UI — `OnboardingFirstSteps` (réécrit, `lib/features/dashboard/presentation/widgets/onboarding_first_steps.dart`)

- Passe de `StatelessWidget` statique à une carte pilotée par `OnboardingProgress`.
- En-tête : titre + sous-titre + indicateur « X/5 » + lien **« Passer »** (dismiss).
- 5 `_StepTile`, chacune :
  - **cochée** (icône check, style atténué) si son signal est vrai ; sinon numéro + chevron.
  - **navigation** : étapes 1-3 → `/properties/new`, `/tenants/new`, `/leases/new`. Étapes 4-5 → `/leases/<firstLeaseId>/payments/new` et `/leases/<firstLeaseId>/receipts`.
  - **dépendance bail** : les étapes 4 et 5 nécessitent un `firstLeaseId`. Tant que `firstLeaseId == null` (pas de bail), elles sont **désactivées** (grisées, non tapables) — le bail est leur prérequis. Une fois un bail créé, elles s'activent.
  - `context.push(route)` (empile depuis l'onglet Accueil, cf. commentaire existant / docs/UX_NAVIGATION.md §5).

### 5. Dismiss local — `onboarding_dismissed_provider.dart`

- `StateNotifier<bool>` adossé à `SharedPreferences` (clé `onboarding_dismissed`), patron identique à `chartPeriodProvider`.
- `dismiss()` pose `true` ; lu par le provider dashboard pour `showOnboarding`.

## Données disponibles (vérifié)

- Collections `properties`, `tenants`, `leases`, `payments` : `landlordId` + `deletedAt` (soft-delete). `receipts` : `landlordId`, immuable/read-only (`isVoided` plutôt que `deletedAt`).
- Routes : `/properties/new`, `/tenants/new`, `/leases/new`, `/leases/:id/payments/new` (PaymentFormPage), `/leases/:id/receipts` (LeaseReceiptsPage) — toutes existantes.
- `SharedPreferences` déjà utilisé (`chartPeriodProvider`, `chart_period_provider.dart`).

## Gestion d'erreur / cas limites

- **Étapes hors ordre** : les signaux sont indépendants ; une étape cochée le reste, une non-cochée reste actionnable. La seule contrainte d'ordre est la dépendance bail des étapes 4-5 (désactivées sans bail).
- **Compte établi sans quittance** : la checklist s'afficherait ; le lien « Passer » la retire définitivement (local). Cas rare (produit pré-lancement).
- **Complétion** : dès qu'un `receipt` existe, `showOnboarding` devient `false` → dashboard normal. Pas de bascule manuelle nécessaire.
- **Erreur de lecture** : mêmes `AsyncValue` error/loading que le dashboard actuel.

## i18n

Nouvelles clés FR/EN (`@description` sur le template EN, parité imposée par `test/l10n/arb_parity_test.dart`) : libellés étapes 4 et 5 (« Enregistrer un paiement », « Générer une quittance »), indicateur « X/5 », lien « Passer », éventuel sous-titre mis à jour. Réutiliser les clés existantes des étapes 1-3 et du titre/sous-titre. `flutter gen-l10n`.

## Tests

- **Unit/repo** (`fake_cloud_firestore` ou fake existant) : `fetchOnboardingProgress` — chaque signal `hasX` juste ; `firstLeaseId` renseigné quand un bail existe, `null` sinon ; filtres `deletedAt`/`landlordId` respectés.
- **Provider** : `showOnboarding` vrai tant que `!hasReceipt` et non dismissed ; faux dès qu'une quittance existe ; faux si dismissed.
- **Widget** : rend 5 étapes ; coches reflètent la progression ; « X/5 » correct ; étapes 4-5 **désactivées** sans `firstLeaseId`, **actives** et routées vers `/leases/<id>/…` avec un bail ; « Passer » masque la carte.
- **i18n** : `arb_parity_test` vert.

## Definition of Done (docs d'état)

`state-keeper` ciblé : `docs/state/routes/dashboard.md` (checklist progressive + dismiss), `docs/state/FEATURES.md` (nouvelle ligne FEAT — onboarding progressif jusqu'à la 1re quittance), `docs/state/CHANGELOG.md`. **Aucune Rules / index / functions / Storage touchés** (100 % client, lecture seule + prefs locales) — rien à déployer côté backend.

## Légal / conformité

- Aucune donnée nouvelle collectée ; lecture des collections déjà possédées par le bailleur. Pas d'impact RGPD.
- La quittance générée reste conforme loi 6 juillet 1989 (inchangée — l'onboarding ne fait qu'y mener).

## Hors scope (V2)

- Célébration/animation à la complétion.
- Progression multi-appareils (le dismiss est local par appareil).
- Étapes optionnelles supplémentaires (uploader un document, inviter un mandataire).
