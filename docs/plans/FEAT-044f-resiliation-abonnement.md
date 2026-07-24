# Plan — [FEAT-044f] Résiliation d'abonnement Pro (conformité loi FR)

> Stack réelle : **Firebase** (Firestore + Cloud Functions Node 20 + Auth) +
> Flutter Web. Stripe Checkout (web) via l'architecture « RevenueCat = plan de
> gestion ». Ce plan NE code rien — il cadre l'implémentation.

## Summary

Ajoute un bouton natif de résiliation (et de réactivation) de l'abonnement
Baillan Pro dans `/profile`, conforme à l'art. **L215-1-1** du Code de la
consommation (« résiliation en 3 clics »). Une **unique Cloud Function callable
paramétrée** `manageSubscription(action: 'cancel' | 'reactivate')` résout
l'abonnement Stripe **côté serveur** depuis `request.auth.uid` (via la metadata
`rc_app_user_id` déjà posée au checkout) et bascule `cancel_at_period_end`.
Le downgrade freemium et la mise à jour de l'état (`proWillRenew` / `proExpiresAt`)
restent **100 % assurés par le chemin existant** RevenueCat → webhook → reconcile ;
FEAT-044f ne réimplémente ni le downgrade ni le gating over-limit (déjà livrés en
FEAT-044). L'UI lit l'état de résiliation depuis Firestore, **sans appel Stripe**.

## Frontière de sécurité (l'équivalent « RLS » à concevoir d'abord)

Le contrôle d'accès tient en un paragraphe : **le client ne fournit jamais
d'identifiant Stripe**. La callable dérive l'UID via `requireAuthUid(request)`
(échoue `unauthenticated` sinon), puis résout l'abonnement par
`stripe.subscriptions.search({query: "metadata['rc_app_user_id']:'<uid>'"})`.
Comme cette metadata a été posée à la valeur `uid` du propriétaire au moment du
checkout (`create_checkout_session.ts`, `RC_APP_USER_ID_METADATA_KEY`), **seul
l'abonnement du demandeur peut être résolu** — il n'existe aucun paramètre client
pouvant pointer vers l'abonnement d'autrui. L'IDOR est structurellement
impossible. Aucune nouvelle collection Firestore, **aucune modification des
règles Firestore** : la callable agit via l'Admin SDK / API Stripe, et le client
ne fait que **lire** son propre doc `landlords/{uid}` (déjà autorisé au owner).

## Décisions de conception (tranchées)

### 1. Résolution de la subscription Stripe depuis l'UID → **Stripe Search API**

**Retenu** : `stripe.subscriptions.search({query: "metadata['rc_app_user_id']:'<uid>'", limit: 20})`,
puis filtrage en mémoire sur les statuts « gérables » et sélection déterministe.

**Alternative rejetée — persister `stripeSubscriptionId` sur `landlords/{uid}`** :
séduisant (lookup O(1), pas de dépendance Search), mais **aucun chemin fiable
pour l'écrire**. On ne reçoit **pas** de webhook Stripe direct (par choix
d'archi : tout transite par RevenueCat). Les options d'écriture sont toutes
plus coûteuses ou fragiles que Search :
- via le webhook RevenueCat : le payload RC n'expose pas de façon documentée
  l'ID de subscription Stripe (couplage aux internes RC → fragile) ;
- via un nouveau callable déclenché sur `/pro/success` : non fiable (l'onglet
  peut se fermer avant le retour) ;
- via un **nouveau webhook Stripe** (`customer.subscription.*`) : c'est la
  solution « propre » long-terme, mais elle ajoute un endpoint, un secret
  (`STRIPE_WEBHOOK_SECRET`), la vérif de signature et de la surface — surdimensionné
  pour v1, et contraire à « default to simple ».

**Justification** : Search fonctionne dès aujourd'hui avec la metadata déjà en
place, zéro persistance nouvelle, zéro nouveau secret, résolution purement
serveur. Caveat connu : la Search API a une **cohérence éventuelle** (un objet
fraîchement créé peut mettre ~1 min à être indexé) — **sans impact ici** car une
résiliation intervient longtemps après la souscription. Rate limit Search
(~20 req/s live) très au-dessus de notre volume.

**Cas « aucune subscription active trouvée »** (abonné mobile IAP, abonnement
déjà terminé, jamais passé par Stripe) → la fonction pure `pickManageableSubscription`
retourne `null` → la callable lève `HttpsError('failed-precondition',
'no_active_web_subscription')`. **Pas de crash**, message d'erreur mappé côté UI.
En amont, l'UI **n'affiche le bouton que pour un abonnement web** (voir §2), donc
ce cas ne devrait survenir qu'en course rare (expiration concurrente).

### 2. Affichage « résiliation programmée » → **lu depuis Firestore, sans Stripe**

Les champs écrits par le webhook (`revenuecat_webhook.ts`) suffisent :
`proEntitlementActive: true` + `proWillRenew: false` + `proExpiresAt` → afficher
« Pro jusqu'au JJ/MM/AAAA, puis Gratuit ». Confirmé : quand l'utilisateur coupe
l'auto-renouvellement sur Stripe (`cancel_at_period_end=true`), Stripe → RevenueCat
émet un event **`CANCELLATION`** → `decideEntitlement('CANCELLATION', …)` renvoie
`{active: (expire>now), willRenew: false}` → le webhook persiste
`proWillRenew:false` en conservant l'accès jusqu'à `proExpiresAt`. La
réactivation émet **`UNCANCELLATION`** (∈ `GRANTING_RENEWABLE`) → `proWillRenew:true`.

**Provider Flutter existant à étendre** : `landlordTierProvider` (StreamProvider
dans `lib/features/auth/data/landlord_tier_repository.dart`) expose déjà un
`LandlordTierSnapshot { tier, anonExpiresAt }` en live depuis `landlords/{uid}`.
Il faut lui ajouter `proWillRenew`, `proExpiresAt`, `proStore`
(et `proEntitlementActive`). C'est le stream que consomment déjà `ProBadge` et
`_ProUpsellCard` — on réutilise, on n'en crée pas un second.

**Lag assumé** : la callable ne résout que Stripe ; l'état Firestore n'est mis à
jour qu'à l'arrivée du webhook RC (quelques secondes à ~1 min). L'UI affiche donc
une **confirmation optimiste immédiate** (snackbar « Résiliation programmée »),
et la carte d'abonnement se met à jour dès que le stream Firestore reflète
`proWillRenew:false`. **La callable N'ÉCRIT PAS Firestore** : on préserve
l'invariant « le webhook est le seul écrivain autoritaire du tier/pro* ». (Si la
QA juge le lag trop visible, un follow-up pourra écrire `proWillRenew` directement
depuis la callable — hors périmètre v1.)

### 3. Réactivation (`cancel_at_period_end=false`) → **DANS le périmètre v1**

Coût quasi nul : une **seule callable paramétrée** `action: 'cancel'|'reactivate'`
+ une branche `pure` `planSubscriptionUpdate`, et le chemin de retour d'état
(`UNCANCELLATION` → `proWillRenew:true`) **existe déjà** dans le webhook. La
réactivation évite qu'un utilisateur ayant résilié par erreur doive re-souscrire
(donc re-payer) → bon pour la rétention ET pour la conformité (symétrie de
l'action). Recommandation : **inclure**.

### 4. IDOR / autorisation → voir « Frontière de sécurité » ci-dessus

`requireAuthUid` + résolution scoping-par-metadata. Aucun ID Stripe côté client.
Note d'injection : l'UID Firebase est alphanumérique URL-safe (pas d'apostrophe),
la requête Search n'est donc pas injectable ; on ajoutera néanmoins un garde-fou
de forme (rejet si l'UID contient une apostrophe) par défense en profondeur.

### 5. Idempotence → **court-circuit sur état déjà atteint**

`planSubscriptionUpdate` renvoie `noop:true` si l'action demande l'état courant
(re-cancel alors que `cancel_at_period_end` déjà `true` ; re-reactivate alors que
déjà renouvelable). La callable retourne alors `{status:'noop', …}` **sans appeler
`subscriptions.update`** → aucun effet de bord, aucun event RC parasite. Même si
on appelait quand même `update` avec la valeur identique, Stripe l'accepte sans
émettre de changement — mais le court-circuit est plus propre.

### 6. Downgrade over-limit → **AUCUN nouveau code ; comportement existant confirmé**

Lecture du gating actuel (FEAT-044) :
- **Création plafonnée serveur** : `createProperty`/`createTenant`
  (`property_tenant.ts`, réservation atomique compteur+gate dans une transaction),
  `createLease`/`updateLease`, `createDocument` (`documents.ts`, count live). Tous
  lisent `landlords/{uid}.subscriptionTier` **en direct** → dès que le tier
  repasse `free`, une nouvelle création au-delà du plafond free est refusée
  `resource-exhausted` (`property_limit_reached`, `tenant_limit_reached`,
  `document_limit_reached`, …).
- **Données existantes jamais touchées** : ni le webhook ni `reconcile` ne
  suppriment quoi que ce soit ; ils ne changent que `subscriptionTier` + `pro*`.
  Un compte à 5 biens qui repasse free **garde ses 5 biens** (lecture/édition OK),
  mais ne peut plus en créer (`5 >= 2`) tant qu'il n'est pas repassé sous le
  plafond (les compteurs se décrémentent au soft-delete → auto-corrigé).
- **Règles Firestore** : `properties/create` et `tenants/create` sont `if false`
  (CF-exclusif) ; les `read`/`update` du owner restent autorisés → aucun changement.

**Politique tranchée** = exactement le comportement déjà en place :
**grandfather en lecture/écriture des données existantes, blocage de la création
au-delà des plafonds free, jamais de suppression de données.** FEAT-044f **ne
touche pas** cette logique. Seule action : **vérifier** en QA (scénario
« 5 biens → downgrade ») et s'assurer que l'UI affiche l'upsell existant sur le
refus (déjà géré côté FEAT-044). Aucune ligne à écrire.

### 7. Conformité légale → section à ajouter dans `docs/LEGAL.md`

Nouvelle section « **Résiliation d'abonnement en ligne (art. L215-1-1 C. conso.,
décret 2023-182)** » : pour un contrat souscrit en ligne (Stripe Checkout), le
professionnel doit offrir une résiliation **aussi simple**, en ligne, gratuite,
en permanence accessible, avec un **récapitulatif avant confirmation**.
Conformité Baillan :
- **3 clics** : (1) ouvrir `/profile` (tuile toujours visible pour un abonné
  web), (2) « Résilier mon abonnement », (3) « Confirmer la résiliation » ;
- **récapitulatif** = la boîte de dialogue de confirmation énonce la date de fin
  d'accès (`proExpiresAt`), le passage automatique en gratuit, et l'absence de
  remboursement au prorata (choix produit = fin de période) ;
- **gratuité + accessibilité permanente** : bouton in-app, aucun tiers, aucune
  friction supplémentaire ;
- **réactivation** possible tant que la période court (symétrie).

## Data model changes

**Aucune migration, aucune nouvelle collection, aucun index, aucun changement de
règles.** Les champs consommés (`proEntitlementActive`, `proWillRenew`,
`proExpiresAt`, `proStore`, `subscriptionTier`) sont déjà écrits par
`revenuecat_webhook.ts` / `reconcile_entitlements.ts` (FEAT-044c). Aucun secret
nouveau : réutilise `STRIPE_SECRET_KEY` (`defineSecret`).

## Backend (Cloud Functions)

### Nouveau fichier — `functions/src/callable/manage_subscription.ts`

Modelé sur `create_checkout_session.ts` : logique pure testable + wrapper `onCall`.

```ts
// Statuts Stripe « gérables » (l'abonnement court encore).
const CANCELABLE_STATUSES = new Set(['active', 'trialing', 'past_due', 'unpaid']);

export type SubscriptionAction = 'cancel' | 'reactivate';

export interface ManageSubscriptionResult {
  status: 'updated' | 'noop';
  cancelAtPeriodEnd: boolean;
}

// PURE — sélectionne l'unique subscription à gérer parmi les résultats Search.
// Filtre les statuts gérables, ignore canceled/incomplete_expired, prend la
// plus récente (created desc) si plusieurs. Retourne null si aucune.
export function pickManageableSubscription(
  subs: Array<{ id: string; status: string; cancel_at_period_end: boolean; created: number }>,
): { id: string; cancel_at_period_end: boolean } | null;

// PURE — décide l'état cible + s'il faut écrire (idempotence).
export function planSubscriptionUpdate(args: {
  action: SubscriptionAction;
  currentCancelAtPeriodEnd: boolean;
}): { targetCancelAtPeriodEnd: boolean; noop: boolean };

export const manageSubscription = onCall({ secrets: [stripeSecret] }, async (request) => { … });
```

**Contrat** :
- **Input** : `{ action: 'cancel' | 'reactivate' }` (validé `requireString` +
  whitelist ; `invalid-argument` sinon).
- **Auth** : `requireAuthUid(request)` → `unauthenticated` si absent.
- **Séquence** :
  1. `uid = requireAuthUid(request)` ; garde-fou de forme UID (pas d'apostrophe).
  2. `stripe.subscriptions.search({ query: "metadata['rc_app_user_id']:'<uid>'", limit: 20 })`.
  3. `target = pickManageableSubscription(search.data)` → si `null`,
     `HttpsError('failed-precondition', 'no_active_web_subscription')`.
  4. `{ targetCancelAtPeriodEnd, noop } = planSubscriptionUpdate({ action, currentCancelAtPeriodEnd: target.cancel_at_period_end })`.
  5. `noop` → return `{ status:'noop', cancelAtPeriodEnd: target.cancel_at_period_end }`.
  6. sinon `stripe.subscriptions.update(target.id, { cancel_at_period_end: targetCancelAtPeriodEnd })`
     → return `{ status:'updated', cancelAtPeriodEnd: updated.cancel_at_period_end }`.
- **Output** : `{ status, cancelAtPeriodEnd }`. **On ne renvoie PAS la date de
  fin** — l'UI lit `proExpiresAt` depuis Firestore (AC #3), ce qui évite le piège
  du champ `current_period_end` (déplacé au niveau item selon l'API version).
- **Effet de bord** : uniquement Stripe. L'état Firestore suit via RC → webhook.

**Cas d'erreur → code HttpsError** :
| Situation | Code | message |
|---|---|---|
| non authentifié | `unauthenticated` | sign-in required |
| action inconnue | `invalid-argument` | action must be 'cancel' or 'reactivate' |
| aucun abonnement web gérable | `failed-precondition` | `no_active_web_subscription` |
| déjà dans l'état cible | (succès) | `status: 'noop'` |
| panne Stripe / réseau | `internal` (ou propagation) | subscription_update_failed |

### `functions/src/index.ts` (modifié)

Ajouter `export { manageSubscription } from './callable/manage_subscription';`
dans la section `// ---------- Callables ----------`.

### Non réimplémenté (réutilisation imposée)

`reconcile_entitlements.ts`, `revenuecat_webhook.ts` : **inchangés**. Le downgrade
et la mise à jour `proWillRenew`/`proExpiresAt` passent par eux.

## Flutter changes

### New files
- `lib/features/paid_plan/data/subscription_repository.dart` — interface
  `SubscriptionRepository { Future<void> cancel(); Future<void> reactivate(); }`
  + `FirebaseSubscriptionRepository` appelant `manageSubscription` via
  `FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable(...)`
  (calque exact de `checkout_repository.dart`). Mappe les `FirebaseFunctionsException`
  (`failed-precondition/no_active_web_subscription`) vers une erreur domaine.
  + provider `subscriptionRepositoryProvider`.
- `lib/features/paid_plan/application/manage_subscription_controller.dart` —
  `AsyncNotifier<void>` (ou contrôleur simple) exposant `cancel()` / `reactivate()`
  avec état loading/error pour piloter le bouton + snackbar.
- `lib/features/paid_plan/presentation/widgets/subscription_section.dart` —
  section « Abonnement Baillan Pro » de `/profile` (ConsumerWidget). Lit
  `landlordTierProvider`. Rendu :
  - `tier != paid` → `SizedBox.shrink()` (rien) ;
  - `paid` + store mobile (`app_store`/`play_store`) → texte info « Gérez votre
    abonnement depuis l'App Store / Google Play » (pas de bouton — hors périmètre v1) ;
  - `paid` + web (ou store inconnu/null → on n'empêche jamais la résiliation) +
    `proWillRenew == true` → « Actif — renouvellement le JJ/MM/AAAA » +
    `OutlinedButton` destructif « Résilier mon abonnement » → dialog de
    confirmation (récapitulatif L215-1-1) → `controller.cancel()` → snackbar ;
  - `paid` + web + `proWillRenew == false` → « Pro jusqu'au JJ/MM/AAAA, puis
    Gratuit » + `OutlinedButton` « Réactiver mon abonnement » → `controller.reactivate()`.
- `test/...` (voir Testing strategy).

### Modified files
- `lib/features/auth/data/landlord_tier_repository.dart` — étendre
  `LandlordTierSnapshot` avec `proWillRenew (bool?)`, `proExpiresAt (DateTime?)`,
  `proStore (String?)`, `proEntitlementActive (bool?)` ; mapper ces champs dans
  `FirestoreLandlordTierRepository.watch`. (StreamProvider inchangé — même source.)
- `lib/features/profile/presentation/profile_page.dart` — insérer
  `const SubscriptionSection()` dans le groupe « Compte » (par ex. juste après
  `_ProUpsellCard`, ou un nouveau `SectionHeader` « Abonnement »). Le widget
  s'auto-masque pour les non-abonnés, donc pas de condition dans la page.
- `lib/l10n/app_fr.arb` **et** `lib/l10n/app_en.arb` — nouvelles clés :
  `subscriptionSectionTitle`, `subscriptionActiveRenews(date)`,
  `subscriptionScheduledCancel(date)` (« Pro jusqu'au {date}, puis Gratuit »),
  `subscriptionCancelButton`, `subscriptionReactivateButton`,
  `subscriptionCancelDialogTitle`, `subscriptionCancelDialogBody(date)`,
  `subscriptionCancelConfirm`, `subscriptionManageOnStore`,
  `subscriptionCancelSuccess`, `subscriptionReactivateSuccess`,
  `subscriptionErrorNoWebSub`, `subscriptionErrorGeneric`. (Format date DD/MM/YYYY,
  fr_FR — cf. LEGAL.md.)

### Providers
- `subscriptionRepositoryProvider` (new)
- `manageSubscriptionControllerProvider` (new, AsyncNotifier)
- `landlordTierProvider` (existant, réutilisé — snapshot enrichi)

### Routes
- **Aucune nouvelle route.** La résiliation vit dans `/profile` (in-page, dialog).
  Route `/pro` (FEAT-044e) inchangée.

## Testing strategy

### Cloud Function (vitest, `functions/src/__tests__/manage_subscription.test.ts`)
Tester les fonctions **pures** (précédent `create_checkout_session.test.ts` : pas
d'I/O Stripe en unit) :
- `planSubscriptionUpdate` :
  - cancel & currently renewing → `{target:true, noop:false}` ;
  - cancel & already `cancel_at_period_end` → `{noop:true}` (idempotence) ;
  - reactivate & `cancel_at_period_end` → `{target:false, noop:false}` ;
  - reactivate & already renewing → `{noop:true}` (idempotence).
- `pickManageableSubscription` :
  - `[]` → `null` (aucun abonnement = user mobile/terminé) ;
  - uniquement `canceled`/`incomplete_expired` → `null` ;
  - une `active` → la retourne ;
  - `active` + `past_due` + `canceled` → ignore canceled, prend la plus récente
    des gérables (`created` desc) ;
  - `trialing` seule → gérable.

### Flutter
- Unit `test/unit/landlord_tier_snapshot_test.dart` : mapping Firestore →
  snapshot (proWillRenew/proExpiresAt/proStore présents, absents/null).
- Widget `test/widget/subscription_section_test.dart` (fake `landlordTierProvider`
  + fake repo) :
  - free/anonymous → section absente ;
  - paid + web + willRenew → bouton « Résilier » visible, libellé renouvellement ;
  - paid + web + !willRenew → « Pro jusqu'au …, puis Gratuit » + « Réactiver » ;
  - paid + store mobile → message « gérer via store », pas de bouton ;
  - tap « Résilier » → dialog affiché → « Confirmer » appelle `repo.cancel()` ;
  - `repo.cancel()` throws `no_active_web_subscription` → snackbar d'erreur mappée.

### Non-régression
- `reconcile_entitlements.test.ts` et `revenuecat_webhook.test.ts` : **doivent
  rester verts sans modification** (aucun changement dans ces fichiers).
- Suite `subscription_tier_test.dart` inchangée.

### QA manuelle (émulateur / staging maîtrisé)
1. Abonné web renouvelable → /profile affiche « Résilier ». Confirmer → snackbar,
   puis (après event RC `CANCELLATION`) la carte passe à « Pro jusqu'au …, puis
   Gratuit ».
2. Ré-cliquer « Résilier » juste après (avant le webhook) → `status:'noop'`,
   pas d'erreur.
3. « Réactiver » → repasse « renouvellement le … » (event `UNCANCELLATION`).
4. **Over-limit** : compte avec 5 biens dont l'abonnement expire (forcer downgrade)
   → les 5 biens restent visibles/éditables ; « Ajouter un bien » est refusé avec
   l'upsell existant. (Vérifie le comportement FEAT-044, ne code rien.)
5. Compte Pro « mobile » (proStore=app_store simulé) → pas de bouton, message store.
6. Autorisation : un compte B ne peut pas résilier l'abonnement de A (aucun
   paramètre pour le tenter — vérif que la Search est bien scoping par uid).

## Risks & hypothèses

- **[R1] Cohérence éventuelle de Stripe Search** : un objet récent peut mettre
  ~1 min à être indexé. Impact quasi nul (on résilie longtemps après la
  souscription). Mitigation possible si observé : fallback `stripe.customers.search`
  puis `subscriptions.list({customer})`, ou (plus lourd) persistance de l'ID.
- **[R2] Lag d'affichage** : entre la callable (Stripe OK) et l'update Firestore
  (webhook RC), la carte peut afficher brièvement l'ancien état. Mitigé par la
  confirmation optimiste (snackbar). Hypothèse : lag ≤ ~1 min acceptable.
- **[R3] Hypothèse RevenueCat** : on suppose que RC émet bien `CANCELLATION` sur
  `cancel_at_period_end=true` et `UNCANCELLATION` sur son retrait (comportement
  documenté RC pour le store Stripe). **À valider en QA** ; si faux, la carte
  n'afficherait pas « puis Gratuit » avant l'`EXPIRATION` finale (le downgrade
  resterait correct, seul l'affichage anticipé manquerait).
- **[R4] `current_period_end` API version** : évité en ne renvoyant PAS la date
  depuis la callable (l'UI lit `proExpiresAt` Firestore). Pas de dette.
- **[R5] `proStore` null sur comptes edge** : on choisit de **montrer** le bouton
  quand le store n'est ni `app_store` ni `play_store` (web ou inconnu) → ne jamais
  cacher le chemin de résiliation à un abonné web (exigence légale). Le pire cas
  (abonné mobile mal étiqueté) tombe sur `no_active_web_subscription`, message clair.
- **[R6] Nommage** : la table de décision du backlog évoquait `cancelSubscription` ;
  ce plan choisit **`manageSubscription(action)`** (une seule fonction, cancel +
  reactivate) — écart volontaire à signaler au product-owner (fonctionnellement
  surensemble, coût moindre).

## Step-by-step execution order

1. **Cloud Function** (`supabase-dev` → ici **firebase/functions-dev**) : créer
   `manage_subscription.ts` (fonctions pures + `onCall`), l'exporter dans
   `index.ts`, écrire `manage_subscription.test.ts`. `npm run lint && build && test`.
2. **Déploiement fonction** : `firebase deploy --only functions:manageSubscription`
   (secret `STRIPE_SECRET_KEY` déjà provisionné) — **après confirmation utilisateur**.
3. **Flutter data/logic** (`flutter-dev`) : enrichir `LandlordTierSnapshot`
   (+ mapping), créer `subscription_repository.dart` +
   `manage_subscription_controller.dart`, ajouter les clés ARB fr/en.
4. **Flutter UI** : `subscription_section.dart` + insertion dans `profile_page.dart`.
5. **Tests** (`qa-tester`) : units + widget ci-dessus ; vérifier non-régression
   webhook/reconcile/tier ; QA manuelle (émulateur) des 6 scénarios.
6. **Légal** : ajouter la section L215-1-1 à `docs/LEGAL.md`.
7. **Revue** : `code-reviewer` + `security-auditor` (focus : scoping metadata,
   pas d'ID Stripe client, idempotence, aucun secret côté client).
8. `flutter analyze` clean + `dart format` ; PR sur branche dédiée (git flow).
```
