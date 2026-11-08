# Plan — [FEAT-056] Abonnements multi-paliers (Pro / Max / Ultra)

> **Statut** : design, non implémenté. Aucun code écrit par ce document.
> **Auteur** : software-architect · **Date** : 2026-07-31 · **Branche cible** : `develop`
> **Périmètre commercial** : défini par le product-owner dans
> [`docs/backlog/056-abonnements-pro-max-ultra.md`](../backlog/056-abonnements-pro-max-ultra.md)
> (livré pendant la rédaction — branchement en **§2.3**). Ce plan ne fixe **aucun
> quota, aucune feature, aucun prix** : il définit l'architecture *paramétrable*
> qui les accueille, et §2.3 vérifie que la grille PO y entre sans rien forcer.

## Summary

Le produit passe d'un unique palier payant (`subscriptionTier == 'paid'`, entitlement
RevenueCat `"Bailan Pro"`) à trois paliers payants ordonnés. La contrainte structurante
n'est pas fonctionnelle mais opérationnelle : **les Cloud Functions sont un déploiement
unique partagé par prod et staging** (ADR 0003), donc tout changement serveur atteint le
runtime de production alors que l'UI prod est fermée (`SUBSCRIPTIONS_ENABLED=false`) et
que des clients mobiles anciens tournent dans la nature.

La décision centrale en découle : **on n'élargit PAS l'enum `subscriptionTier`**. Il reste
`anonymous | free | paid` (= *classe d'accès*, ce que les clients existants savent lire) et
on ajoute un champ **additif** `planLevel ∈ {pro, max, ultra}` (= *palier commercial*).
Un client ancien continue de voir `paid` et garde son accès ; aucune migration de données ;
le rollback est un pur revert de code.

Le second pilier est une **table de configuration unique** (`config/entitlements.json`)
d'où sont *générés* le miroir Dart et le miroir TypeScript, avec un script de parité en CI :
c'est le seul remède structurel au risque n°1 (client et serveur en désaccord sur un quota).

---

## 0. État des lieux vérifié (2026-07-31)

Vérifié contre le code, pas contre les shards — deux dérives constatées :

| Élément | Réalité code | Shard `docs/state/functions/account.md` |
|---|---|---|
| `functions/src/callable/manage_subscription.ts` | existe (FEAT-044f, cancel/reactivate) | **non documenté** |
| Routes `/pro/success` et `/pro/cancel` | **existent** (`app_router.dart` L234-247, `ProSuccessPage`/`ProCancelPage`) | documentées comme « n'existent pas encore » |

> À signaler au `state-keeper` en fin de feature (DoD n°5). Ce plan se fie au code.

### Points de gating existants (exhaustif)

| # | Fichier | Fonction / ligne | Quota | Code d'erreur | Enforcement |
|---|---|---|---|---|---|
| 1 | `functions/src/callable/property_tenant.ts` | `createProperty` (~L210-223), `limitForTier` L58, `FREE_PROPERTY_LIMIT` L47 | biens actifs | `property_limit_reached` | **serveur** |
| 2 | `functions/src/callable/property_tenant.ts` | `createTenant` (~L340-350), `FREE_TENANT_LIMIT` L48 | locataires actifs | `tenant_limit_reached` | **serveur** |
| 3 | `functions/src/callable/lease_payment.ts` | `createLease` (~L246-256), `activeLeaseLimitForTier` L104, `FREE_ACTIVE_LEASE_LIMIT` L103 | baux actifs | `lease_limit_reached` | **serveur** |
| 4 | `functions/src/callable/lease_payment.ts` | `updateLease` (~L459-466) | baux actifs | `lease_limit_reached` | **serveur** |
| 5 | `functions/src/callable/documents.ts` | `assertDocumentQuota` L101-124, `limitForTier` L80, `FREE_DOCUMENT_LIMIT` L73 | documents actifs (`count()` live) | `document_limit_reached` | **serveur** |
| 6 | `lib/features/simulator/application/scenario_limit_controller.dart` | `scenarioLimitForTierProvider` | scénarios sauvegardés | — | **client seul** ⚠️ |
| 7 | `lib/features/charge_regularization/presentation/widgets/charge_regularization_section.dart` L61-78 | `isPaid` | feature régularisation | — | **client seul** ⚠️ |
| 8 | `lib/features/simulator/presentation/scenario_comparison_page.dart` L30-40 | `isPaid` | feature comparaison scénarios | — | **client seul** ⚠️ |
| 9 | `functions/src/callable/documents.ts` L68 | `MAX_BYTES = 10 * 1024 * 1024` | taille max **par fichier** | `invalid-argument` | **serveur, mais uniforme** — devient un quota par palier (§2.4) |

⚠️ **#6/#7/#8 ne sont pas enforcés serveur aujourd'hui.** Avec trois paliers payants, un
quota purement client devient un différenciateur commercial contournable. Le plan traite ce
point (§5.3) sans le transformer en chantier bloquant : on **déclare la classe
d'enforcement dans la table de config** et on ferme le cas #6 (le seul qui écrit en base).

`limitForTier` est **dupliqué à l'identique trois fois** (property_tenant, documents,
lease_payment), chacun avec ses constantes, plus un quatrième exemplaire en Dart
(`subscription_tier.dart`). Quatre sources de vérité pour une même grille : c'est
précisément ce que §2 supprime.

---

## 1. Modèle de données

### 1.1 Options comparées

#### Option A — élargir l'enum : `subscriptionTier ∈ {anonymous, free, pro, max, ultra}`

`paid` disparaît (ou devient un alias legacy parsé en `pro`).

- ✅ Un seul champ, un seul ordre, sémantique limpide.
- ✅ Pas de couple de champs à garder cohérent.
- ❌ **Rédhibitoire** : `SubscriptionTier.fromRaw` retombe sur `anonymous` pour toute valeur
  inconnue (`subscription_tier.dart` L17-27). Un client Flutter déployé (surtout **mobile**,
  version-laggé par les stores, non forçable) qui reçoit `"ultra"` traite un **abonné payant
  comme un anonyme** : `propertyLimit = 0`, `activeTenantLimit = 0`, `activeLeaseLimit = 0`,
  `documentLimit = 0`, registre inaccessible. C'est le pire échec possible : on verrouille
  le client qui paie le plus cher.
- ❌ Nécessite une migration write-heavy de tous les `landlords` payants existants, avec
  fenêtre d'incohérence pendant le batch, et un rollback qui doit **ré-écrire les données**.
- ❌ Le webhook (déploiement partagé prod+staging) écrirait `pro` en prod dès son merge,
  sans qu'aucun client prod ne sache le lire.

On *pourrait* corriger `fromRaw` d'abord (« fail-up » vers `paid`) puis migrer plus tard —
mais on ne peut pas garantir la disparition des vieilles builds mobiles. Le risque n'est
pas bornable dans le temps.

#### Option B — additif : `subscriptionTier` inchangé + `planLevel` (RECOMMANDÉE)

`subscriptionTier ∈ {anonymous, free, paid}` conserve exactement sa sémantique actuelle
(*classe d'accès*). Nouveau champ `planLevel ∈ {pro, max, ultra} | null` (*palier
commercial*), non-null **si et seulement si** `subscriptionTier == 'paid'`.

- ✅ **Rétrocompatibilité totale sans migration** : les docs `paid` existants restent
  valides tels quels ; un client ancien lit `paid` et garde un accès illimité.
- ✅ **Mode de défaillance bénin** : un vieux client sur-autorise (il montre une feature Max
  à un abonné Pro) au lieu de sur-restreindre. Le serveur refuse l'action → l'utilisateur
  voit une erreur, mais **ne perd jamais l'accès qu'il a payé**. Sur-autoriser en UI coûte
  une friction ; sur-restreindre coûte un abonné et un litige.
- ✅ **Rollback = revert de code, zéro donnée à défaire**. `planLevel` et `entitlements`
  sont additifs : le code ancien les ignore.
- ✅ Le déploiement partagé des Functions devient sûr par construction : le webhook continue
  d'écrire `subscriptionTier: 'paid'` comme aujourd'hui, il ajoute seulement `planLevel`.
- ⚠️ Deux champs à garder cohérents. Mitigé par : un **seul écrivain** (le webhook, plus le
  cron), une **seule fonction pure** de dérivation (`deriveEffectivePlan`) partagée par les
  deux, et un test d'invariant (§10).
- ⚠️ `paid` devient un terme un peu creux (« payant, niveau non précisé »). Acceptable :
  c'est exactement l'information dont un client ancien a besoin.

#### Option C — rang numérique `planRank: int` (10/20/30) à la place d'une chaîne

- ✅ Ordre total trivial, robuste aux valeurs inconnues (`rank >= 20` marche même si le
  client ne connaît pas le nom du palier).
- ❌ Illisible en console Firestore, et un rang orphelin (`25`) est indébuggable.
- ❌ Ne résout pas le problème du vieux client (qui ne lit pas le champ du tout).
- **Verdict** : rejeté comme champ stocké. Le rang reste **dérivé** de la table de config
  (§2), donc modifiable sans migration.

#### Option D — sous-document `landlords/{uid}/subscription/current`

- ❌ Une lecture supplémentaire dans chaque callable de gating (5 points, dont plusieurs en
  transaction) ; des règles Firestore en plus ; aucun bénéfice ici (le doc landlord n'est
  pas près de la limite de 1 Mio).
- **Verdict** : rejeté, complexité non payée.

### 1.2 Décision

> **Option B.** `subscriptionTier` reste `anonymous | free | paid` et garde sa sémantique.
> On ajoute `planLevel: 'pro' | 'max' | 'ultra' | null` (client-immuable) et une map
> serveur `entitlements` (état par palier). Aucune migration des docs existants ; les
> abonnés actuels sont **grandfathered en `pro`** par dérivation, pas par écriture.

### 1.3 Champs `landlords/{uid}`

**Inchangés** : `subscriptionTier`, `proEntitlementActive`, `proStore`, `proProductId`,
`proExpiresAt`, `proWillRenew`, `proSince`, `proLastEventAtMs` (ces champs `pro*` deviennent
le **reflet du palier effectif** — voir §3.4 — pour que `SubscriptionSection` et
`LandlordTierSnapshot` continuent de fonctionner sans changement).

**Nouveaux** :

```
landlords/{uid}
  planLevel: string | null          // 'pro' | 'max' | 'ultra' ; null si non payant
                                    // CLIENT-IMMUABLE (rules), écrit par webhook + cron
  entitlements: map | absent        // état par palier, écrit UNIQUEMENT par Admin SDK
    <levelId>:                      // clé = notre id de palier ('pro'|'max'|'ultra'),
                                    // PAS l'id RevenueCat (découplage vendeur/stockage)
      active: bool
      expiresAt: timestamp | null
      willRenew: bool
      productId: string | null
      store: string | null          // valeurs de storeOf() : app_store|play_store|web|promo
      lastEventAtMs: int            // garde d'ordre PAR PALIER (cf. §3.3)
```

**Pourquoi la map `entitlements` et pas juste `planLevel`** : un event RevenueCat ne décrit
que les entitlements **qu'il concerne**, pas l'état global de l'abonné. Sans état par
palier, un `EXPIRATION` sur `pro` reçu après un `INITIAL_PURCHASE` sur `ultra` ne
permettrait pas de savoir si l'utilisateur garde Ultra. La map rend chaque event
*localement* applicable et le palier effectif *dérivable* — c'est l'invariant qui protège
du sur-facturé comme du sous-servi.

**Clé de la map = notre id de palier**, pas la chaîne RevenueCat : l'id RC actuel est
`"Bailan Pro"` (avec un `l` manquant — *typo historique, load-bearing, à ne jamais
corriger*, cf. §3.1) et contient un espace. Stocker des clés Firestore vendeur-dépendantes
nous lierait à un renommage RC.

### 1.4 Invariants du modèle

| # | Invariant | Garant |
|---|---|---|
| **I1** | `subscriptionTier == 'paid'` ⟺ `planLevel != null` ⟺ ∃ palier actif dans `entitlements` | `deriveEffectivePlan` (fonction pure unique) |
| **I2** | Le client n'écrit jamais `subscriptionTier`, `planLevel`, `entitlements`, `pro*` | Firestore Rules (§6) |
| **I3** | Un doc sans `planLevel` mais `subscriptionTier == 'paid'` vaut **`pro`** | `resolvePlan()` côté serveur, `PlanEntitlement.fromRaw()` côté Dart |
| **I4** | Un `planLevel` **inconnu** du client sur un doc `paid` vaut **`pro`** (fail-UP), jamais `anonymous` | `PlanLevel.fromRaw` (§1.5) |
| **I5** | On n'introduit **jamais** un palier payant *sous* le plus bas connu | discipline produit, notée en tête de `config/entitlements.json` |

**I5 mérite un mot** : le fail-up de I4 suppose que « palier inconnu ⇒ au moins aussi bon
que Pro ». Si un jour on lançait une offre payante *moins-disante* que Pro (« Baillan
Léger »), un vieux client la traiterait comme Pro et sur-autoriserait. La règle : une offre
inférieure ne s'introduit pas comme un nouveau `planLevel`, elle se traite comme une
révision de la grille `free` ou via une bascule de version explicite. À écrire en
commentaire dans le JSON canonique.

### 1.5 Modèle Dart

`lib/features/auth/domain/subscription_tier.dart` : l'enum reste, **les 5 getters de
plafonds sont supprimés** (ils deviennent des lookups dans la table générée, §2).

```dart
// lib/features/auth/domain/plan_level.dart  (nouveau)
enum PlanLevel { pro, max, ultra }
// rank, id, labelKey : lus dans la table générée, pas codés en dur ici.

// PlanLevel.fromRaw(String? raw, {required SubscriptionTier tier}) :
//   tier != paid            -> null
//   raw connu               -> le palier
//   raw null   & tier==paid -> PlanLevel.pro   (grandfathering, I3)
//   raw inconnu& tier==paid -> PlanLevel.pro   (fail-UP, I4 — JAMAIS anonymous)
```

```dart
// lib/features/auth/domain/plan_entitlement.dart  (nouveau)
class PlanEntitlement {
  final SubscriptionTier tier;
  final PlanLevel? level;          // non-null ssi tier == paid  (I1)

  int get rank;                    // anonymous=0, free=1, sinon level.rank (table)
  bool atLeast(PlanLevel l);       // « au moins Max » = rank >= table.rankOf(l)
  int? quota(PlanQuota q);         // null = illimité
  bool has(PlanFeature f);
}
```

`atLeast` est **le seul** comparateur autorisé côté UI ; toute comparaison `== SubscriptionTier.paid`
dans le code existant (15 fichiers) migre vers `atLeast(PlanLevel.pro)` ou `has(PlanFeature.x)`.
Interdire les comparaisons d'`index` d'enum Dart (l'ordre de déclaration n'est pas un contrat) :
le rang vient **toujours** de la table.

`LandlordTierSnapshot` (`landlord_tier_repository.dart`) gagne `planLevel` et expose
`PlanEntitlement get plan`. Aucune suppression de champ → aucun test existant cassé.

---

## 2. Table de configuration unique des droits

C'est le cœur du plan, et le remède au risque n°1 (**client autorise ce que le serveur
refuse, ou l'inverse**). Aujourd'hui la grille existe en **4 exemplaires** recopiés à la
main, avec des commentaires « miroir de… » qui n'ont aucune force exécutoire.

### 2.1 Source canonique

Un fichier unique versionné, **rempli par le product-owner** :

```
config/entitlements.json
```

```jsonc
{
  "schemaVersion": 1,
  // INVARIANT I5 : ne jamais introduire un palier payant de rang inférieur à 'pro'.
  "levels": [
    { "id": "pro",   "rank": 10, "rcEntitlementId": "Bailan Pro",
      "stripePriceParam": { "monthly": "STRIPE_PRICE_PRO_MONTHLY",
                            "annual":  "STRIPE_PRICE_PRO_ANNUAL" },
      "priceLabel": { "monthly": "7,99 €", "annual": "79 €" },
      "purchasable": true,  "priceIndicative": false, "recommended": false },
    { "id": "max",   "rank": 20, "rcEntitlementId": "<À DÉFINIR — dashboard RC>",
      "stripePriceParam": { "monthly": "STRIPE_PRICE_MAX_MONTHLY",
                            "annual":  "STRIPE_PRICE_MAX_ANNUAL" },
      "priceLabel": { "monthly": "14,99 €", "annual": "149 €" },
      "purchasable": false, "priceIndicative": true,  "recommended": true },
    { "id": "ultra", "rank": 30, "rcEntitlementId": "<À DÉFINIR — dashboard RC>",
      "stripePriceParam": { "monthly": "STRIPE_PRICE_ULTRA_MONTHLY",
                            "annual":  "STRIPE_PRICE_ULTRA_ANNUAL" },
      "priceLabel": { "monthly": "24,99 €", "annual": "249 €" },
      "purchasable": false, "priceIndicative": true,  "recommended": false }
  ],
  // null = illimité. Valeurs PO — celles ci-dessous ne sont que les valeurs ACTUELLES
  // reportées à l'identique pour 'pro' (aucune régression pour un abonné existant).
  "quotas": {
    "properties":   { "errorCode": "property_limit_reached", "enforcement": "server",
                      "values": { "anonymous": 0, "free": 2, "pro": null, "max": null, "ultra": null } },
    "tenants":      { "errorCode": "tenant_limit_reached",   "enforcement": "server",
                      "values": { "anonymous": 0, "free": 3, "pro": null, "max": null, "ultra": null } },
    "activeLeases": { "errorCode": "lease_limit_reached",    "enforcement": "server",
                      "values": { "anonymous": 0, "free": 2, "pro": null, "max": null, "ultra": null } },
    "documents":    { "errorCode": "document_limit_reached", "enforcement": "server",
                      "values": { "anonymous": 0, "free": 10, "pro": null, "max": null, "ultra": null } },
    "scenarios":    { "errorCode": "scenario_limit_reached", "enforcement": "server",
                      "values": { "anonymous": 1, "free": 3, "pro": null, "max": null, "ultra": null } },
    // Quota de TAILLE (octets par fichier), pas de comptage — cf. §2.3.
    // `unit` distingue les deux familles pour le formatage et pour le générateur.
    "documentMaxBytes": { "errorCode": "file_too_large", "enforcement": "server",
                      "unit": "bytes",
                      "values": { "anonymous": 0, "free": 10485760, "pro": 10485760,
                                  "max": 26214400, "ultra": 52428800 } }
  },
  "features": {
    "chargeRegularization": { "minLevel": "pro", "enforcement": "client", "status": "shipped" },
    "scenarioComparison":   { "minLevel": "pro", "enforcement": "client", "status": "shipped" },
    "prioritySupport":      { "minLevel": "max", "enforcement": "none",   "status": "shipped" },
    // `status: "planned"` = feature annoncée sur /pro mais non construite : l'UI
    // affiche l'argumentaire + capture d'intérêt, jamais un chemin d'accès.
    "paymentReminders":     { "minLevel": "max",   "enforcement": "server", "status": "planned", "feat": "FEAT-031" },
    "listings":             { "minLevel": "max",   "enforcement": "server", "status": "planned", "feat": "FEAT-051" },
    "accountingExport":     { "minLevel": "ultra", "enforcement": "server", "status": "planned", "feat": "FEAT-032" },
    "collaborators":        { "minLevel": "ultra", "enforcement": "server", "status": "planned", "feat": "FEAT-034" }
  }
}
```

Deux champs de méta comptent autant que les chiffres :

- **`enforcement`** : `server` (une Cloud Function refuse), `client` (UI seule, contournable
  par un appel direct — assumé et documenté), `none` (promesse commerciale hors produit,
  ex. support prioritaire). Rend explicite ce qui est *réellement* verrouillé. Une feature
  différenciante Max/Ultra marquée `client` est un signal d'alerte pour le code-reviewer.
- **`errorCode`** : le contrat d'erreur entre serveur et client. Ces chaînes existent déjà
  et sont mappées côté Flutter — les figer dans la table empêche de les casser par
  inadvertance.

### 2.2 Mécanisme anti-divergence (génération + garde CI)

**Deux miroirs générés, jamais écrits à la main :**

| Cible | Fichier généré | Générateur |
|---|---|---|
| Dart (runtime web/mobile — pas d'accès disque) | `lib/features/auth/domain/plan_matrix.g.dart` | `tool/gen_entitlements.dart` |
| TypeScript (bundle Functions — hors `rootDir` du JSON) | `functions/src/entitlements/plan_matrix.generated.ts` | `functions/tool/gen_entitlements.mjs` |

Les deux fichiers portent un en-tête `// GENERATED — do not edit. Source: config/entitlements.json`
et un `sourceSha` (SHA-256 du JSON canonique) inclus **dans le contenu généré**.

**Garde CI** — `scripts/check-entitlements-parity.sh`, ajouté au workflow à côté de
`scripts/check-db-isolation.sh` (même convention : un script shell qui fait échouer la PR) :

1. relance les deux générateurs ;
2. `git diff --exit-code` sur les deux fichiers générés → échec si l'un est périmé ;
3. compare les deux `sourceSha` → échec s'ils diffèrent (protège d'un générateur cassé) ;
4. vérifie que le JSON est bien formé et que **chaque palier de `levels` a une entrée dans
   chaque `quotas[].values`** (pas de trou → pas de `undefined` traité comme 0 ou ∞).

**Filet d'exécution** (les générateurs peuvent être justes et le *consommateur* faux) :

- `test/unit/plan_matrix_parity_test.dart` — lit `config/entitlements.json` **depuis le
  disque** (`dart:io` est disponible sous `flutter test`) et compare valeur par valeur à
  `plan_matrix.g.dart`. C'est un test qui échoue si quelqu'un édite le fichier généré à la
  main sans toucher au JSON.
- `functions/src/__tests__/plan_matrix_parity.test.ts` — symétrique côté Jest.
- `functions/src/__tests__/quota_contract.test.ts` — pour chaque quota `enforcement:
  "server"`, assert qu'il existe un point d'appel `quotaLimit(plan, '<quota>')` dans le code
  des callables (grep AST ou simple liste explicite maintenue avec un test de complétude).

Pourquoi générer plutôt que « JSON importé directement des deux côtés » : le TS pourrait
importer le JSON (`resolveJsonModule`), mais il est **hors `functions/`** donc hors du
bundle déployé ; et Dart ne peut pas lire un asset en tests unitaires *et* en runtime web de
la même façon. La génération règle les deux, au prix d'un script de 60 lignes par langage.

**Alternative rejetée** : « table écrite à la main des deux côtés + un test qui lit le
JSON ». Moins de machinerie, mais on garde deux fichiers éditables à la main : la CI
attrape la divergence *après* qu'elle a été écrite, et rien n'empêche de « corriger le test »
plutôt que le code. La génération rend la divergence **inexprimable**.

### 2.3 Branchement sur la grille product-owner

La grille livrée (`docs/backlog/056-abonnements-pro-max-ultra.md` §2, §4, §6) entre dans la
table telle quelle, à **trois ajustements de schéma près** qu'elle a révélés :

**(a) Un quota de TAILLE, pas seulement de comptage.** « Taille max. par document uploadé :
10 / 10 / 25 / 50 Mio » est le premier quota différenciant réellement construit — et il ne
ressemble à aucun quota existant : c'est une borne **par fichier**, pas un compteur cumulé.
Conséquence :

- point de gating n°9 (§0) : `documents.ts` L68 `MAX_BYTES = 10 * 1024 * 1024` devient
  `quotaLimit(plan, 'documentMaxBytes')` ;
- le type de retour reste `int | null`, mais le champ `unit: "bytes"` pilote le formatage
  (« 25 Mio ») et évite qu'un développeur additionne des octets et des compteurs ;
- ⚠️ **le contrôle doit rester serveur.** L'UI *doit* pré-vérifier la taille (pour ne pas
  faire uploader 40 Mio à un compte Pro avant de refuser), mais `createDocument` reste la
  source de vérité. Bon côté : c'est le seul quota du plan dont le dépassement coûte de la
  bande passante — l'UI qui filtre en amont n'est pas un gate, c'est de la courtoisie ;
- le message d'erreur doit **nommer le palier minimal suffisant** (« passez à Max pour
  25 Mio ») : c'est exactement l'upsell contextuel demandé au §3 de la grille PO, et il est
  dérivable de la table (plus petit palier dont la valeur couvre la taille du fichier).
  Nouveau code d'erreur `file_too_large` (aujourd'hui un `invalid-argument` générique).

**(b) Un palier peut être affiché mais non achetable.** La grille acte que **Max et Ultra
ne sont pas vendables au lancement** (leurs features distinctives — FEAT-031/051/032/034 —
ne sont pas construites) : ils s'affichent avec un badge « bientôt disponible », un prix
marqué *indicatif* et une capture d'intérêt, jamais un bouton de paiement. C'est une
**propriété du palier**, pas un état de l'UI :

- `purchasable: bool` et `priceIndicative: bool` dans `levels[]` ;
- **serveur** : `createCheckoutSession` refuse un palier `purchasable: false` avec
  `failed-precondition / level_not_purchasable`, **avant même** de regarder le price ID.
  Deux verrous indépendants (ce flag + `price_not_configured`) valent mieux qu'un ;
- **client** : la carte rend `_ComingSoonNotify` (widget existant, aucun nouveau composant)
  avec `notifyMe(features: ['pro_pricing_max'])` — la capture d'intérêt taguée par palier
  que demande la grille PO, sur le mécanisme `paid_plan_interest` déjà en place ;
- ouvrir Max plus tard = passer **un booléen à `true`** dans le JSON (+ créer les prix
  Stripe et l'entitlement RC). Pas de PR de code. C'est le test que la paramétrisation
  tient : les user stories FEAT-056f et FEAT-056g de la grille PO se réduisent alors à
  leur chantier métier propre + une ligne de config.

**(c) Une feature peut être annoncée avant d'exister.** `status: 'planned'` + `feat: 'FEAT-0XX'`
distingue « verrouillé parce que vous n'avez pas le bon palier » de « pas encore construit ».
Les deux se rendent différemment (upsell vs « bientôt »), et un `hasFeature()` sur une
feature `planned` doit renvoyer `false` **quel que soit le palier**, y compris Ultra — sinon
on promet à un abonné Ultra un export comptable qui n'existe pas.

Enfin, la grille confirme deux choix de ce plan :

- **Pro = copie exacte de l'actuel `paid`** (mêmes quotas, même prix 7,99/79 €) → la
  migration des abonnés existants est un **non-événement**, exactement ce que promet
  l'Option B (§1.2). Aucun abonné ne perd ni ne gagne quoi que ce soit au déploiement.
- Les prix Max/Ultra étant **indicatifs**, le risque R8 (prix affiché ≠ prix Stripe) est
  temporairement neutralisé pour eux — mais il redevient actif le jour de leur ouverture.
  La case de QA « prix affiché == prix Stripe » est donc à rejouer **par palier, à chaque
  ouverture**, pas une seule fois au lancement.

### 2.4 Contrat d'API de la table

Identique des deux côtés (mêmes noms, pour que la revue croisée soit triviale) :

```
rankOf(levelId) -> int
levelForRank(rank) -> levelId
quotaLimit(plan, quota) -> int | null         // null = illimité
hasFeature(plan, feature) -> bool             // false si status == 'planned', TOUS paliers
errorCodeFor(quota) -> string
levelForRcEntitlement(rcId) -> levelId | null // null = entitlement étranger → ignoré
isPurchasable(levelId) -> bool                // §2.3(b)
minLevelFor(feature) -> levelId               // upsell : « passez à … »
minLevelForQuota(quota, needed) -> levelId | null  // upsell contextuel (ex. taille fichier)
```

---

## 3. Entitlements RevenueCat

### 3.1 Trois entitlements distincts (recommandé)

| Option | Verdict |
|---|---|
| **A — 3 entitlements RC** (`Bailan Pro`, + 2 nouveaux) | ✅ **Retenue** |
| B — 1 entitlement + résolution par `product_id` | ❌ Rejetée |
| C — 1 entitlement « accès » + 3 entitlements « niveau » | ❌ Rejetée (redondant avec A) |

**Pourquoi A** : RevenueCat modélise nativement le « qui a droit à quoi » par entitlement ;
un abonné peut en porter plusieurs pendant une transition, ce qui est exactement
l'information dont on a besoin pour un downgrade différé (§3.5). L'event porte
`entitlement_ids`, donc la résolution est directe et ne dépend d'aucune convention de
nommage de produit.

**Pourquoi pas B** : les product IDs se multiplient par plateforme (3 paliers × 2
périodicités × {Stripe, App Store, Play Store} = jusqu'à 18 identifiants), plus les
promos et les prix legacy. Chaque ID non mappé serait un abonné sans palier — donc un
`resource-exhausted` sur un compte qui paie. La table de mapping deviendrait le vrai
point de fragilité, avec une maintenance manuelle à chaque nouveau prix.

**Contrainte gelée** : `PRO_ENTITLEMENT_ID = "Bailan Pro"` (un seul `l` — typo historique)
est **la clé effective des abonnés existants**. La renommer côté dashboard RC ferait passer
tous leurs events par `levelForRcEntitlement() → null → ignored`, donc plus aucune
expiration ni renouvellement appliqué : silencieux, et coûteux. La chaîne migre telle quelle
dans `config/entitlements.json` avec un commentaire explicite. Les deux nouveaux ids sont à
créer dans le dashboard RC par le PO/ops et à reporter dans le JSON (`<À DÉFINIR>` en
attendant — le générateur doit **refuser** de produire un miroir contenant `<À DÉFINIR>`,
ce qui empêche mécaniquement de déployer une config incomplète).

### 3.2 Résolution du palier depuis un event

```
levels(event) = { levelForRcEntitlement(id) | id ∈ (entitlement_ids ?? [entitlement_id]) }
              \ {null}
```

- Ensemble vide → `ignored` (comportement actuel préservé : un entitlement étranger ne
  touche rien).
- Sinon, l'event s'applique **uniquement aux paliers qu'il mentionne** (invariant I2 ci-dessous).

`decideEntitlement(type, expirationMs, nowMs)` est **conservée telle quelle** (pure, testée,
mapping type → `{active, willRenew}` inchangé). Elle décrit désormais l'état *d'un palier*,
pas *du compte*.

### 3.3 Invariants du webhook multi-palier (section money-critical)

| # | Invariant | Conséquence si violé |
|---|---|---|
| **W1** | Un event ne modifie **que** les paliers qu'il mentionne | Un `EXPIRATION` sur Pro effacerait un Ultra actif → abonné payant verrouillé |
| **W2** | La garde d'ordre est **par palier** (`entitlements.<lvl>.lastEventAtMs`), pas globale | Un `EXPIRATION` Pro (T1) reçu après un `INITIAL_PURCHASE` Ultra (T2) serait jeté comme « stale » alors qu'il concerne un autre palier |
| **W3** | Le palier effectif = **max(rank)** parmi les paliers actifs et non expirés | Facturer Ultra et servir Pro (ou l'inverse) |
| **W4** | `subscriptionTier` = `paid` ⟺ au moins un palier actif ; sinon `free` | Perte ou octroi indu de l'accès |
| **W5** | Un `rcEntitlementId` inconnu est **ignoré**, jamais deviné/normalisé | Un entitlement de test RC accorderait Ultra |
| **W6** | `proSince` n'est jamais réécrit après la première activation | Perte de l'audit d'ancienneté |
| **W7** | Le webhook reste **idempotent** : rejouer le même event ne change rien | Doublons de facturation apparents dans les logs, faux positifs de support |

**Pseudo-algorithme** (dans la transaction, `applyRevenueCatEvent`) :

```
1. type == "TEST"                         -> ignored
2. affected = levels(event) ; si vide     -> ignored
3. uid manquant / $RCAnonymousID:*        -> ignored
4. decision = decideEntitlement(...) ; null -> ignored
5. tx.get(landlords/{uid}) ; absent       -> no_landlord ; isAnonymous -> ignored
6. states = data.entitlements ?? legacyStates(data)        // §3.4
7. applied = 0
   pour lvl ∈ affected :
     si event_timestamp_ms < states[lvl].lastEventAtMs  -> skip (stale sur CE palier)
     states[lvl] = { active: decision.active, expiresAt, willRenew: decision.willRenew,
                     productId, store: storeOf(event.store),
                     lastEventAtMs: event_timestamp_ms }
     applied++
   si applied == 0                        -> stale
8. eff = deriveEffectivePlan(states, nowMs)               // pure, partagée avec le cron
9. tx.update : entitlements=states,
               subscriptionTier = eff.active ? 'paid' : 'free',
               planLevel        = eff.levelId,             // null si !active
               proEntitlementActive = eff.active,
               proExpiresAt/proWillRenew/proStore/proProductId = miroir du palier EFFECTIF,
               proSince = eff.active ? (data.proSince ?? serverTimestamp()) : (data.proSince ?? null),
               proLastEventAtMs = max(data.proLastEventAtMs ?? 0, event_timestamp_ms),
               updatedAt = serverTimestamp()
   -> applied
```

`proLastEventAtMs` global est **conservé** (max des events vus) : il n'est plus une garde
d'ordre mais reste gelé par les règles Firestore et sert au diagnostic. Ne pas le supprimer
— les règles actuelles le comparent (`firestore.rules` L160) et un champ absent ferait
échouer la rule d'update pour tous les clients.

### 3.4 Compatibilité des abonnés existants (`legacyStates`)

Aucun doc existant n'a de map `entitlements`. Fonction pure de repli, appliquée **en
lecture** (jamais de batch de migration) :

```
legacyStates(data):
  si data.proEntitlementActive === true :
    { pro: { active: true, expiresAt: data.proExpiresAt, willRenew: data.proWillRenew ?? true,
             productId: data.proProductId, store: data.proStore,
             lastEventAtMs: data.proLastEventAtMs ?? 0 } }
  sinon: {}
```

Conséquence : le tout premier event reçu après le déploiement matérialise la map à partir de
l'état legacy, sans jamais rétrograder l'abonné. **C'est ce qui rend le déploiement Functions
partagé (prod + staging) sûr** : aucune écriture préalable requise en prod.

### 3.5 Upgrades / downgrades entre paliers payants

RevenueCat émet `PRODUCT_CHANGE` (déjà dans `GRANTING_RENEWABLE`). Deux comportements
store-dépendants, tous deux **corrects par construction** avec W1+W3 :

| Cas | Ce que RC rapporte | Effet W1+W3 | Résultat |
|---|---|---|---|
| **Upgrade immédiat** (Stripe proraté, Apple upgrade) | `PRODUCT_CHANGE` portant le nouvel entitlement (ex. `ultra`) ; l'ancien expire ou est révoqué → `EXPIRATION` sur `pro` | `ultra` devient actif ; `pro` reste actif jusqu'à son `EXPIRATION` | Palier effectif = `ultra` **immédiatement** ✅ |
| **Downgrade différé** (Apple/Google : effectif en fin de période) | Le nouvel entitlement (`pro`) devient actif à la date de renouvellement ; `ultra` reste actif jusqu'à son échéance | Chevauchement : max(rank) = `ultra` | Le client garde **Ultra jusqu'à la fin de la période payée**, puis bascule Pro à l'`EXPIRATION` d'Ultra ✅ (juridiquement et commercialement correct) |
| **Downgrade immédiat** (Stripe, si on choisit la proration immédiate) | `pro` actif, `ultra` révoqué → `EXPIRATION` sur `ultra` | `ultra` inactif → max(rank) = `pro` | Bascule immédiate ✅ |

**Le piège à ne pas reproduire** : dériver le palier de `entitlement_ids` du *seul* event
courant. Sur un downgrade différé, l'event ne mentionne que `pro` → on rétrograderait un
client qui a payé Ultra jusqu'à la fin du mois. C'est exactement pourquoi la map d'état
existe (§1.3).

**Chevauchement et `expiresAt`** : `deriveEffectivePlan` filtre sur
`state.active === true && (expiresAt == null || expiresAt > nowMs)`. Un palier « actif » mais
échu ne compte pas — le cron finira par le nettoyer, mais la dérivation est déjà correcte
sans lui.

### 3.6 Interaction avec la garde d'ordre

La garde devient **par palier** (W2). Le raisonnement : deux paliers ont des cycles de vie
indépendants ; l'horodatage d'un event sur `ultra` ne dit rien de la fraîcheur d'un event sur
`pro`. Conserver une garde globale produirait des pertes d'events silencieuses lors de tout
changement de palier — la classe de bug la plus chère (on facture Ultra et on sert Pro,
sans erreur nulle part).

Test obligatoire (§10) : `INITIAL_PURCHASE ultra @ T2` puis `EXPIRATION pro @ T1` (arrivée
désordonnée) → doit rester `ultra`, et `pro` doit passer inactif.

---

## 4. Stripe Checkout et changement de palier

### 4.1 Price IDs

Six `defineString` (les price IDs ne sont **pas** des secrets ; ils restent hors
Secret Manager, comme aujourd'hui) :

```
STRIPE_PRICE_PRO_MONTHLY    (existe)   STRIPE_PRICE_PRO_ANNUAL    (existe)
STRIPE_PRICE_MAX_MONTHLY    (nouveau)  STRIPE_PRICE_MAX_ANNUAL    (nouveau)
STRIPE_PRICE_ULTRA_MONTHLY  (nouveau)  STRIPE_PRICE_ULTRA_ANNUAL  (nouveau)
```

Les **noms de ces paramètres** sont déclarés dans `config/entitlements.json`
(`stripePriceParam`), pas devinés par concaténation : un palier ajouté au JSON sans son
paramètre fait échouer la génération. Les deux noms existants sont conservés → **aucune
reconfiguration du Pro en production**.

Alternative rejetée : un seul paramètre JSON `STRIPE_PRICES='{"pro":{"monthly":"price_..."}}'`.
Une virgule oubliée casse les six offres d'un coup, et l'erreur n'apparaît qu'au premier
checkout.

### 4.2 Signature de la callable (rétrocompatible)

```ts
// Nouvelle forme
{ level: 'pro'|'max'|'ultra', period: 'monthly'|'annual' } -> { url, sessionId }
// Forme legacy TOUJOURS acceptée (clients web/mobile déployés)
{ plan: 'monthly'|'annual' }  ==  { level: 'pro', period: <plan> }
```

Le shim de compatibilité n'est **pas optionnel** : le déploiement Functions étant partagé,
la version prod du client (et surtout les builds mobiles des stores) continuera d'envoyer
`{plan}` pendant des semaines. Normalisation en une fonction pure exportée et testée :

```ts
parseCheckoutRequest(data) -> { level: LevelId, period: 'monthly'|'annual' }
// - level absent          -> 'pro'
// - period absent         -> data.plan
// - valeur inconnue       -> HttpsError('invalid-argument')
// - les deux absents      -> HttpsError('invalid-argument')
```

**Retrait du shim** : PR dédiée (§11, PR-7), conditionnée à une version plancher mobile
effectivement diffusée. Tant que la condition n'est pas remplie, on ne touche pas.

### 4.3 `buildCheckoutSessionParams`

Reste **pure et testable**, signature élargie :

```ts
buildCheckoutSessionParams({
  uid, level, period,
  config: { prices: Record<`${LevelId}_${Period}`, string | undefined>, baseUrl },
  customerEmail,
}) -> Stripe.Checkout.SessionCreateParams
```

Changements :
- **`isPurchasable(level) == false` → `HttpsError('failed-precondition', 'level_not_purchasable')`,
  vérifié AVANT le price** : au lancement, Max et Ultra sont affichés mais non vendables
  (§2.3-b). Deux verrous indépendants (ce flag et `price_not_configured`) ;
- résolution du price via `prices[`${level}_${period}`]` ;
- **si le price est vide/absent → `HttpsError('failed-precondition', 'price_not_configured')`**.
  C'est le garde-fou qui rend le déploiement partagé sûr : tant que les prix Max/Ultra ne
  sont pas configurés (prod), un appel malicieux ou une UI en avance échoue proprement au
  lieu de créer une session sur un price vide ;
- `success_url` gagne `&level={level}` pour que `/pro/success` affiche le bon palier ;
- `metadata` : on **ajoute** `baillan_plan_level: level` (en plus de `rc_app_user_id`, qui
  ne change pas). Utile au support et au rapprochement Stripe ↔ RC ; **jamais utilisé comme
  source de vérité du droit** (la source reste l'entitlement RC).

Inchangé et critique : `rc_app_user_id` posé sur la **session ET** `subscription_data.metadata`
(RevenueCat lit les deux), plus `client_reference_id`.

### 4.4 Changement de palier pour un abonné déjà payant

**Ne jamais ouvrir une seconde Checkout Session à un abonné actif.** Cela créerait une
deuxième subscription Stripe → double prélèvement, deux entitlements, un support furieux.
Garde-fou serveur : si `parseCheckoutRequest` réussit mais que le compte est déjà `paid`
(lecture de `landlords/{uid}` via `dbForRequest`), `createCheckoutSession` renvoie
`failed-precondition / already_subscribed_use_change_plan`.

| Option | Verdict |
|---|---|
| Nouvelle Checkout Session | ❌ double abonnement |
| `stripe.subscriptions.update` (changement d'item) | ✅ **Retenue** |
| Stripe Billing Portal | ❌ surface de config supplémentaire, duplique le parcours L215-1-1 déjà construit, contrôle plus faible sur les libellés FR |

**Implémentation** : nouvelle action dans `manage_subscription.ts` (fichier déjà IDOR-proof :
l'abonnement est résolu par `metadata['rc_app_user_id'] == uid`, aucun identifiant Stripe ne
vient du client).

```ts
{ action: 'change_plan', level: 'pro'|'max'|'ultra', period: 'monthly'|'annual' }
  -> { status: 'updated'|'noop', level, period, effectiveAt }
```

Séquence :
1. `requireAuthUid` + `assertSafeUid` (inchangés) ;
2. `pickManageableSubscription` (réutilisé tel quel) ; `null` → `failed-precondition /
   no_active_web_subscription` (abonné IAP mobile → l'UI renvoie vers le store) ;
3. résolution du nouveau price (mêmes params qu'en §4.1) ; absent → `price_not_configured` ;
4. si le price cible == price courant → `noop` (idempotence, **aucun appel Stripe** → aucun
   event RC parasite ; même politique que `planSubscriptionUpdate`) ;
5. `stripe.subscriptions.update(subId, { items: [{ id: <itemId courant>, price: <target> }],
   proration_behavior: 'create_prorations', payment_behavior: 'pending_if_incomplete' })` ;
6. **n'écrit RIEN dans Firestore** — le palier reste accordé par le seul webhook RC
   (`PRODUCT_CHANGE`). C'est la règle d'or de l'ADR 0002, à ne pas contourner « pour que
   l'UI réagisse plus vite ».

Fonction pure à extraire et tester : `planLevelChange({currentPriceId, targetPriceId,
currentRank, targetRank}) -> {noop, direction: 'upgrade'|'downgrade'}`.

**Politique de proration — décision à faire valider par le PO (risque §Risks R3)** :
recommandation v1 = **immédiat et proraté dans les deux sens**, le downgrade générant un
avoir sur les factures suivantes (pas de remboursement). C'est le comportement Stripe le
plus simple, cohérent avec un self-service, et il évite d'introduire des Subscription
Schedules. Il doit être **explicitement annoncé dans l'UI avant confirmation** (« Le
changement prend effet immédiatement. La différence est calculée au prorata et reportée en
crédit sur vos prochaines factures — aucun remboursement n'est effectué. »). Le downgrade
différé en fin de période (via `SubscriptionSchedule`) est noté P2.

⚠️ **Asymétrie web/mobile** : sur iOS/Android, le changement de palier passe
obligatoirement par le store (StoreKit / Google Play Billing), donc `change_plan` ne
s'applique **qu'aux abonnés `proStore == 'web'`**. Pour `app_store`/`play_store`,
l'UI affiche le message « gérez votre abonnement depuis le store » déjà présent
(`subscriptionManageOnStore`). Aucune régression, mais à écrire noir sur blanc.

### 4.5 Impact sur `manageSubscription` (cancel/reactivate)

Aucun changement de logique : `cancel_at_period_end` est indépendant du palier.
`pickManageableSubscription`, `planSubscriptionUpdate`, `parseAction`, `assertSafeUid`
restent intacts — `parseAction` accepte simplement `'change_plan'` en plus. Les libellés du
dialogue de résiliation deviennent paramétrés par le nom du palier (§8).

---

## 5. Enforcement serveur

### 5.1 Le contrôle générique de substitution

Nouveau module `functions/src/entitlements/` :

- `plan_matrix.generated.ts` — la table (générée, §2.2) ;
- `plan.ts` — logique pure :
  ```ts
  resolvePlan(landlordData) -> { tier, levelId }      // applique I3 (paid sans planLevel -> pro)
  quotaLimit(plan, quota)   -> number | null          // null = illimité
  deriveEffectivePlan(states, nowMs) -> {...}         // partagée webhook + cron (§3.3)
  legacyStates(landlordData) -> states                // §3.4
  levelForRcEntitlement(rcId) -> LevelId | null
  ```

**Volontairement PAS de helper qui lit Firestore.** Les 5 points de gating tournent
aujourd'hui à l'intérieur de transactions où le snapshot `landlords` est **déjà lu**
(`property_tenant.ts` L210, `lease_payment.ts` L241/L459) ; un helper `assertQuota(db, uid, …)`
ferait une seconde lecture, hors transaction pour documents et **en violation du contrat
transactionnel** ailleurs. On substitue donc du calcul pur, pas de l'I/O.

Chaque call site devient :

```ts
const plan  = resolvePlan(landlordData);
const limit = quotaLimit(plan, 'properties');
if (limit !== null && count >= limit) {
  throw new HttpsError('resource-exhausted', errorCodeFor('properties'));
}
```

Le `throw` **reste au call site** pour préserver à l'identique les codes d'erreur
(`property_limit_reached`, `tenant_limit_reached`, `lease_limit_reached`,
`document_limit_reached`) que le client Flutter mappe déjà.

### 5.2 Liste exhaustive des modifications

| # | Fichier | Cible | Action |
|---|---|---|---|
| 1 | `functions/src/callable/property_tenant.ts` | `limitForTier` L58, `FREE_PROPERTY_LIMIT` L47, `FREE_TENANT_LIMIT` L48 | **supprimer** |
| 2 | idem | `createProperty` ~L210-223 | `resolvePlan` + `quotaLimit(plan,'properties')` |
| 3 | idem | `createTenant` ~L340-350 | `resolvePlan` + `quotaLimit(plan,'tenants')` |
| 4 | `functions/src/callable/lease_payment.ts` | `activeLeaseLimitForTier` L104, `FREE_ACTIVE_LEASE_LIMIT` L103 | **supprimer** |
| 5 | idem | `createLease` ~L246-256 | `quotaLimit(plan,'activeLeases')` |
| 6 | idem | `updateLease` ~L459-466 | `quotaLimit(plan,'activeLeases')` |
| 7 | `functions/src/callable/documents.ts` | `limitForTier` L80, `FREE_DOCUMENT_LIMIT` L73 | **supprimer** |
| 8 | idem | `assertDocumentQuota` L101-124 | `resolvePlan` + `quotaLimit(plan,'documents')` |
| 8b | idem | `MAX_BYTES` L68 + sa validation | `quotaLimit(plan,'documentMaxBytes')` ; erreur `file_too_large` nommant `minLevelForQuota('documentMaxBytes', size)` (§2.3-a) |
| 9 | `functions/src/http/revenuecat_webhook.ts` | `PRO_ENTITLEMENT_ID`, `applyRevenueCatEvent` | multi-palier (§3.3) ; `decideEntitlement`, `storeOf`, `isAuthorizedWebhook` **inchangées** |
| 10 | `functions/src/scheduled/reconcile_entitlements.ts` | tout le cœur | §7 |
| 11 | `functions/src/callable/create_checkout_session.ts` | signature + `buildCheckoutSessionParams` | §4 |
| 12 | `functions/src/callable/manage_subscription.ts` | `parseAction` + action `change_plan` | §4.4 |
| 13 | **nouveau** `functions/src/callable/scenarios.ts` | `createScenario` | §5.3 |
| 14 | `functions/src/index.ts` | export de `createScenario` | — |

Le tier brut n'est plus lu à la main (`typeof landlord.subscriptionTier === "string" ? … : "anonymous"`,
répété 5 fois) : `resolvePlan` encapsule ce fallback **une** fois, avec le même défaut
sécuritaire (`anonymous` si absent/illisible — ici sur-restreindre est correct, c'est un
défaut *serveur* de dernier recours, pas la lecture d'un client obsolète).

### 5.3 Les quotas « client seul » (#6/#7/#8)

- **#6 scénarios** (`scenarios`, écriture Firestore directe depuis le client) : **à fermer**.
  C'est le seul des trois qui crée de la donnée, donc le seul contournable avec un effet
  persistant. Les règles Firestore ne savent pas compter → il faut une callable
  `createScenario` sur le modèle exact de `createProperty` (transaction, lecture landlord,
  `quotaLimit(plan,'scenarios')`, `resource-exhausted / scenario_limit_reached`), et le
  passage de la rule `investment_scenarios/create` à `allow create: if false`.
  **Coût réel** (repository + contrôleur + tests + migration du chemin d'écriture) : à
  cadrer comme un lot séparé (PR-2b) et **ne pas bloquer FEAT-056 dessus** si le PO ne
  différencie pas les scénarios entre paliers. Décision à trancher au vu de la grille PO.
- **#7 régularisation de charges** et **#8 comparaison de scénarios** : calculs *lecture
  seule* sur des données que l'utilisateur possède déjà. Un gating serveur n'apporterait
  rien (le calcul peut être refait à la main). Ils restent `enforcement: "client"`, et la
  table le **déclare** pour que ce soit un choix documenté et non un oubli. Si le PO en fait
  un différenciateur Max/Ultra structurant, l'alternative est de déplacer le calcul
  côté serveur (callable qui renvoie le résultat) — à chiffrer alors séparément.

---

## 6. Règles Firestore et index

### 6.1 Ce qui change

**`landlords/{uid}` — UPDATE (compte complet)**, à la suite des gels existants (L136-160) :

```js
// FEAT-056 : palier commercial et état des entitlements écrits EXCLUSIVEMENT par
// revenueCatWebhook / reconcileEntitlements (Admin SDK, bypass rules). Même
// raisonnement que les champs pro* : un client qui pourrait écrire planLevel
// s'offrirait Ultra gratuitement.
&& request.resource.data.get('planLevel', null) == resource.data.get('planLevel', null)
&& request.resource.data.get('entitlements', {}) == resource.data.get('entitlements', {})
```

**`landlords/{uid}` — UPDATE (anonyme)** (L166-189) : mêmes deux lignes. Un anonyme ne peut
de toute façon pas être payant (le webhook l'ignore, W-`isAnonymous`), mais la défense en
profondeur coûte deux lignes.

**`landlords/{uid}` — CREATE (compte complet, L94)** et **CREATE (anonyme, L115)** :

```js
&& request.resource.data.get('planLevel', null) == null
&& !request.resource.data.keys().hasAny(['entitlements'])
```

Sans cela, un client provisionne son propre doc (le provisioning est 100 % client, cf.
`auth_repository.dart`) **avec** `planLevel: 'ultra'` : `subscriptionTier` serait bien `free`
(déjà contraint L94) mais un futur bug de lecture qui ferait confiance à `planLevel` seul
serait exploitable. On ferme la porte à la création, pas seulement à la mise à jour.

> ⚠️ L'égalité de map (`request.resource.data.get('entitlements', {}) == resource.data.get(...)`)
> est valide en règles Firestore mais compare en profondeur. Vu la taille (3 clés max), le
> coût est négligeable. **Alternative plus propre, optionnelle (PR séparée)** : remplacer la
> liste croissante de gels par
> `request.resource.data.diff(resource.data).affectedKeys().hasAny(SERVER_OWNED_FIELDS) == false`.
> C'est une réécriture d'une rule critique → à faire *seule*, couverte par les tests de
> règles, jamais mélangée à FEAT-056.

### 6.2 Ce qui ne change pas — et pourquoi `subscriptionTier` reste client-immuable

**Politique en un paragraphe** : le doc `landlords/{uid}` est lisible et modifiable par son
seul propriétaire authentifié (`isOwner` + `isFullyAuthed`), mais l'ensemble des champs qui
déterminent *ce qu'il a le droit de faire* — `subscriptionTier`, `planLevel`, `entitlements`,
`pro*`, `activePropertiesCount`, `activeTenantsCount`, `activeLeasesCount` — est **gelé
côté client** : toute écriture doit les reproduire à l'identique. Ces champs n'ont qu'un
écrivain, l'Admin SDK (webhook RevenueCat, cron de réconciliation, callables de gating), qui
bypasse les règles. Le `delete` est interdit (soft-delete par callable). La conséquence est
que *le droit ne peut jamais être auto-attribué* : un client qui veut Ultra doit passer par
Stripe → RevenueCat → webhook. C'est la même politique qu'avant, étendue mot pour mot aux
deux nouveaux champs.

Le passage à trois paliers **augmente** l'enjeu de cette immuabilité : hier, forcer
`subscriptionTier: 'paid'` était le seul gain possible ; demain, `planLevel: 'ultra'` est un
gain gradué et donc une cible plus attractive. Aucune raison n'existe de relâcher : le
client n'a **jamais** besoin d'écrire son palier, y compris pour l'affichage optimiste post-
checkout (`/pro/success` doit attendre le webhook, pas peindre un état).

### 6.3 Index

- **Aucun index composite nouveau requis.** Le cron interroge `proEntitlementActive == true`
  (égalité simple) — inchangé.
- **Optionnel** (`firestore.indexes.json`, section `fieldOverrides`) : désactiver
  l'indexation automatique de la map `entitlements` (`{"collectionGroup":"landlords",
  "fieldPath":"entitlements","indexes":[]}`). Trois sous-champs × 6 attributs = ~18 entrées
  d'index par doc payant, pour zéro requête. Gain de coût marginal aujourd'hui, réflexe sain.
- Si le PO veut plus tard un tableau de bord par palier (`where planLevel == 'ultra'`), un
  index à champ unique suffira (automatique).

---

## 7. Cron `reconcileEntitlements`

Le downgrade n'est plus binaire. Trois faits nouveaux :

1. **Une expiration d'Ultra ne signifie plus « retour au gratuit »** si un Pro reste actif.
2. **Un `PRODUCT_CHANGE` manqué** produit une dérive de *palier* alors que l'échéance reste
   dans le futur — donc **invisible** pour le filtre actuel (« ne réconcilier que les
   échéances dépassées », L118-120). C'est un trou de couverture nouveau et coûteux (on peut
   facturer Ultra et servir Pro pendant des semaines).
3. RevenueCat reste **la source de vérité**, y compris pour le palier.

### 7.1 Changements

**Fetcher** — passe de « échéance de l'entitlement pro » à « état de tous nos entitlements » :

```ts
export type EntitlementStatesFetcher =
  (uid: string) => Promise<Record<LevelId, { expiresMs: number | null }>>;
// Lit body.subscriber.entitlements et ne retient que les rcEntitlementId connus,
// re-clés vers nos levelId via levelForRcEntitlement(). Toujours injectable.
```

**Cœur** — `reconcileLandlord` recompose la map d'état à partir de la réponse RC puis appelle
**la même `deriveEffectivePlan` que le webhook** (c'est le point clé : une seule définition
du « palier effectif », donc pas de désaccord possible entre le temps réel et le cron).

**Issues** enrichies : `unchanged | renewed | level_changed | downgraded_free | failed`.

**Filtre en mémoire** — **supprimer le `continue` sur échéance future** (L119-120) et
réconcilier tous les docs `proEntitlementActive == true` dans la limite. Justification :
l'ensemble est borné par définition (c'est la base d'abonnés), et c'est la seule façon
d'attraper un `PRODUCT_CHANGE` manqué. Coût : 1 appel REST RC par abonné et par jour —
négligeable au volume MVP. Quand la base dépasse `BATCH_SIZE = 200`, ajouter une pagination
par curseur `__name__` persistée dans un petit doc de contrôle (`_ops/reconcileCursor`) —
**à noter comme dette explicite dans le code**, pas à implémenter maintenant.

### 7.2 Invariant de sécurité du cron (révisé)

| Ancien | Nouveau |
|---|---|
| « Ne fait **jamais** d'upgrade » | « Ne fait **jamais** passer `free → paid`. Peut corriger le **palier** d'un compte **déjà payant**, dans les deux sens. » |

Justification : monter `pro → ultra` sur un compte déjà `paid` n'est pas un octroi d'accès,
c'est une **correction de palier** appuyée sur la source de vérité (API RC, authentifiée par
la clé serveur `REVENUECAT_API_KEY`). Refuser cette correction laisserait durablement un
client sous-servi alors qu'il paie. Le garde-fou qui compte —
« aucun chemin automatique de `free` vers un accès payant hors webhook » — est **maintenu
intact** : `if (!wasActive) return 'unchanged'` reste la première branche.

À logger explicitement (`level_changed pro→ultra uid=…`) : toute montée de palier par le
cron signale un webhook manqué, donc un problème d'intégration à investiguer.

⚠️ **Routage Firestore** : `reconcileEntitlements` utilise aujourd'hui `admin.firestore()`
(L166) — légal car les crons/triggers sont volontairement sur `(default)` (exception
documentée de `scripts/check-db-isolation.sh`). **Ne pas « corriger » ce point** dans cette
feature : conséquence assumée, un abonnement de test staging n'est pas réconcilié par le
cron. À vérifier manuellement pendant la recette staging (§9.4).

---

## 8. UI

### 8.1 `/pro` — trois offres

`lib/features/paid_plan/presentation/pro_pricing_page.dart` : refonte. Le `maxWidth: 480`
actuel (L88) devient ~1120.

**Responsive — reprendre le pattern FEAT-055** (`scenario_comparison_page.dart` : cartes en
mobile / tableau en desktop, via `LayoutBuilder` + `lib/core/ui/breakpoints.dart`) :

| Largeur | Rendu |
|---|---|
| `< Breakpoints.mobile` (600) | **Colonne** de 3 cartes pleine largeur, palier `recommended` en premier et visuellement mis en avant. Toggle mensuel/annuel unique, au-dessus. Liste des features **par carte** (pas de tableau). |
| `600 – 1024` (tablette) | Colonne de cartes plus compactes (2 colonnes si la place le permet ; **ne pas** compresser 3 cartes sur 600-800 px). |
| `>= Breakpoints.tablet` (1024) | **Row** de 3 cartes de largeur égale (`Expanded` + `IntrinsicHeight` pour aligner les CTA) + **tableau comparatif** Free / Pro / Max / Ultra en dessous. |

- Un **seul** `_PlanToggle` global (mensuel/annuel) : trois toggles indépendants seraient
  incompréhensibles. Comportement conservé.
- Le badge « recommandé » et l'ordre des cartes viennent de la **table de config**
  (`recommended: true`), pas du code : le PO change la mise en avant sans PR Dart.
- **Prix** : aujourd'hui codés en dur (`'79'` / `'7,99'`, L199). Les faire remonter dans la
  table de config (`priceLabel: {monthly, annual}` en chaîne déjà formatée FR/EN) ou dans
  l'ARB. Les prix Stripe restent la source de vérité *facturante* ; l'affichage n'en est
  qu'un miroir → **ajouter une case de QA manuelle « prix affiché == prix Stripe »** au
  moment du lancement (aucun mécanisme automatique proposé : lire l'API Stripe depuis le
  client est exclu).
- **État par carte, en fonction du palier courant** (`PlanEntitlement.rank`) :

| Situation | CTA |
|---|---|
| non payant | « S'abonner » → `createCheckoutSession(level, period)` |
| payant, carte == palier courant | « Votre offre actuelle » (désactivé) |
| payant, carte de rang supérieur | « Passer à Max/Ultra » → `manageSubscription(change_plan)` + dialog de proration |
| payant, carte de rang inférieur | « Revenir à Pro » → même chemin, dialog explicitant l'avoir |
| payant via `app_store`/`play_store` | CTA désactivé + `subscriptionManageOnStore` |
| palier `purchasable: false` (Max/Ultra au lancement) | `_ComingSoonNotify` (widget existant) + badge « Bientôt disponible » + prix marqué *indicatif* ; capture d'intérêt taguée `notifyMe(features: ['pro_pricing_<level>'])`. **Jamais de chemin de paiement.** |
| `Env.subscriptionsEnabled == false` | `_ComingSoonNotify` sur **les trois** cartes (le gate global prime sur `purchasable`) |

Le gate `Env.subscriptionsEnabled` est **conservé tel quel** : c'est lui qui garantit que la
prod reste fermée pendant que staging teste.

### 8.2 Badge et chip de palier

- `pro_badge.dart` (L13 : `if (tier != SubscriptionTier.paid) return SizedBox.shrink()`) →
  affiche le libellé du palier effectif (Pro / Max / Ultra) avec une couleur distincte par
  palier, **issue des design tokens** (`lib/core/theme/`), pas de couleurs littérales.
- `tier_chip.dart` (simulateur, L72) → même traitement ; le `case SubscriptionTier.paid`
  devient un switch sur `PlanLevel`.
- Prévoir le cas `paid` sans `planLevel` (I3) : rendu « Pro ». Aucun état vide possible.

### 8.3 Section abonnement du profil

`subscription_section.dart` :
- garde `if (snapshot?.tier != SubscriptionTier.paid) return SizedBox.shrink()` (correct et
  suffisant : `atLeast(PlanLevel.pro)` y est équivalent) ;
- affiche le **nom du palier courant** dans l'en-tête (`subscriptionSectionTitleWithLevel`) ;
- ajoute un CTA « Changer d'offre » → `/pro` (la page pricing sert de sélecteur ; pas de
  second écran de sélection à maintenir), **masqué si `proStore ∈ {app_store, play_store}`** ;
- résiliation/réactivation : logique inchangée, libellés paramétrés par le palier.

### 8.4 Nouvelles clés i18n (FR + EN, `lib/l10n/app_{fr,en}.arb`)

À créer (les 44 clés `pro*`/`subscription*` existantes sont **conservées** ; celles listées
« modifiées » changent de valeur, pas de nom) :

```
// Paliers — noms et accroches
planLevelPro / planLevelMax / planLevelUltra
planLevelProTagline / planLevelMaxTagline / planLevelUltraTagline
planRecommendedBadge                     "Recommandé"

// Page /pro multi-offres
proPricingHeadlineMulti                  "Choisissez votre offre"
proPricingCompareTitle                   "Comparer les offres"       (tableau desktop)
proPricingColumnFree                     "Gratuit"
proCurrentPlanLabel                      "Votre offre actuelle"
proUpgradeToLevel                        "Passer à {level}"          (placeholder)
proDowngradeToLevel                      "Revenir à {level}"         (placeholder)
proQuotaUnlimited                        "Illimité"
proQuotaValue                            "{count}"                   (plural)

// Changement de palier
planChangeDialogTitle                    "Changer d'offre ?"
planChangeUpgradeBody                    "…prend effet immédiatement…prorata…"
planChangeDowngradeBody                  "…crédit sur vos prochaines factures, aucun remboursement…"
planChangeConfirm                        "Confirmer le changement"
planChangeSuccess                        "Votre offre est en cours de mise à jour…"
planChangeErrorNoWebSub                  "…gérez votre offre depuis l'App Store / Google Play."
planChangeErrorPriceUnavailable          "Cette offre n'est pas encore disponible."
planChangeErrorGeneric                   "Une erreur est survenue. Veuillez réessayer."

// Modifiées (valeur seulement)
subscriptionSectionTitle                 -> "Abonnement {level}"
subscriptionCancelDialogBody             -> mentionne le palier
proSuccessTitle / proSuccessBody         -> mentionnent le palier (query param ?level=)
proAlreadySubscribed                     -> "Abonnement {level} actif"
scenarioLimitReached* / *LimitReached*   -> upsell vers le palier MINIMAL qui débloque
                                            (calculé depuis la table, pas codé en dur)
```

Dernier point non trivial : les messages d'upsell (« Passez à Pro pour… ») doivent nommer le
**palier minimal suffisant** pour la feature demandée, dérivé de `features[].minLevel`. Un
message qui pousse vers Ultra pour une feature incluse dans Pro est un bug commercial.

### 8.5 Fichiers Flutter touchés

**Nouveaux** : `lib/features/auth/domain/plan_level.dart`,
`lib/features/auth/domain/plan_entitlement.dart`,
`lib/features/auth/domain/plan_matrix.g.dart` *(généré)*,
`lib/features/paid_plan/presentation/widgets/plan_card.dart`,
`lib/features/paid_plan/presentation/widgets/plan_comparison_table.dart`,
`lib/features/paid_plan/application/plan_change_controller.dart`,
`lib/features/paid_plan/data/plan_change_repository.dart`,
`tool/gen_entitlements.dart`.

**Modifiés** : `subscription_tier.dart` (retrait des 5 getters),
`landlord_tier_repository.dart` (+`planLevel`, +`plan`),
`pro_pricing_page.dart`, `pro_badge.dart`, `subscription_section.dart`,
`checkout_controller.dart` + `checkout_repository.dart` (signature `level`/`period`),
`tier_chip.dart`, `scenario_limit_controller.dart`, `saved_scenarios_row.dart`,
`scenario_limit_reached_modal.dart`, `scenario_comparison_page.dart`,
`charge_regularization_section.dart`, `lease_detail_page.dart`, `profile_page.dart`,
`pro_success_page.dart` (lecture de `?level=`), `app_fr.arb`, `app_en.arb`.

### 8.6 Providers

```
planMatrixProvider        Provider<PlanMatrix>              // table générée (constante)
planEntitlementProvider   Provider<PlanEntitlement>         // dérivé de landlordTierProvider
quotaLimitProvider        Provider.family<int?, PlanQuota>  // remplace scenarioLimitForTierProvider
hasFeatureProvider        Provider.family<bool, PlanFeature>// remplace les `== SubscriptionTier.paid`
planChangeControllerProvider  AsyncNotifierProvider         // manageSubscription(change_plan)
```

`scenarioLimitForTierProvider` est conservé en `@Deprecated` un temps (il est consommé par
`scenarioLimitController`) ou migré dans la même PR — au choix de l'implémenteur, mais
**pas de double source** : il doit déléguer à `quotaLimitProvider`.

### 8.7 Routes

**Aucune route à ajouter.** `/pro`, `/pro/success`, `/pro/cancel` existent déjà
(`app_router.dart` L227-247). Seul changement : `/pro/success` lit le query param `level`
(`state.uri.queryParameters['level']`) pour personnaliser le message — avec repli sur un
texte générique (le param est *cosmétique*, jamais une source de droit).

---

## 9. Migration et rollout staging

### 9.1 Ce qui rend ce rollout sûr

Trois propriétés, à vérifier en revue avant tout merge :

1. **Le webhook continue d'écrire `subscriptionTier: 'paid'`** → un client prod ancien (web
   ou mobile) ne voit aucun changement de comportement.
2. **`legacyStates` évite toute migration** → aucun batch d'écriture sur la prod, donc aucune
   fenêtre d'incohérence, donc aucun rollback de données.
3. **`price_not_configured` + entitlements RC inexistants** → même déployé, le code
   multi-palier est inerte en prod tant que les prix Stripe et les entitlements RC ne sont
   pas créés.

### 9.2 Ordre de déploiement

| Étape | Quoi | Où | Pourquoi cet ordre |
|---|---|---|---|
| 1 | `firestore.rules` (gel de `planLevel`/`entitlements`) | CI auto : `develop`→`staging`, `main`→`(default)` | Geler **avant** qu'un écrivain existe. Inoffensif sur des docs qui n'ont pas les champs. |
| 2 | Cloud Functions (webhook, cron, quotas, checkout, change_plan) | **manuel**, déploiement **unique partagé** | Le serveur doit comprendre les paliers avant que la moindre UI ne les propose. |
| 3 | Config RevenueCat : 2 nouveaux entitlements + mapping produits | dashboard RC (**projet unique, partagé prod/staging**) | Créer un entitlement n'accorde rien tant qu'aucun produit n'y est rattaché ni acheté. |
| 4 | Prix Stripe (test mode) ×4 + params `STRIPE_PRICE_{MAX,ULTRA}_*` | `firebase functions:config`/params, déploiement | Après 2, sinon `price_not_configured` (comportement voulu). |
| 5 | Flutter (domaine + UI 3 offres) | `develop` → hosting `stage` | Dernier : il consomme tout le reste. |
| 6 | Recette staging complète (§9.4) | stage.baillan.com | — |
| 7 | Merge `develop` → `main` | prod, `SUBSCRIPTIONS_ENABLED=false` | L'UI prod reste fermée ; la bascule commerciale est une **décision séparée** (cf. issue #138, clé `sk_test_`). |

**Rappel critique** : rien de tout cela ne doit être exécuté dans le cadre de ce plan.
Aucun `firebase deploy`, aucun appel Stripe/RevenueCat n'a été fait pendant sa rédaction.

### 9.3 Discipline ADR 0003 (à répéter à l'implémenteur)

`revenueCatWebhook` route via `dbForLandlordUid(uid)` qui **cherche le doc landlord en prod
d'abord**, puis dans staging. Conséquence opérationnelle non négociable :

> **Pour tout test de paiement sur staging, utiliser un uid (compte) qui n'a JAMAIS existé
> en production.** Si l'uid existe des deux côtés, le webhook écrira le palier dans la base
> **prod** — c'est-à-dire qu'un achat de test offrira Ultra à un compte de production.

Protocole : créer le compte de test **exclusivement** depuis `stage.baillan.com` (donc dans
la base `staging`), noter l'uid, et vérifier avant l'achat que `landlords/{uid}` **n'existe
pas** dans `(default)`. Ne jamais réutiliser un uid de test entre deux campagnes de recette
sans cette vérification.

Rappel connexe : le cron `reconcileEntitlements` tourne sur `(default)` uniquement → un
abonnement de test staging n'est **pas** réconcilié automatiquement. Le tester en invoquant
le cœur (`reconcileExpiredEntitlements`) en test unitaire avec un fetcher simulé, pas en
production.

### 9.4 Recette staging (scénarios manuels)

Sur `stage.baillan.com`, `SUBSCRIPTIONS_ENABLED=true`, Stripe **test mode**, uid neuf :

1. Compte free → `/pro` : les 3 cartes s'affichent, responsive mobile (< 600) et desktop
   (≥ 1024) vérifiés, quotas cohérents avec la table.
2. Achat **Pro mensuel** → webhook → `subscriptionTier: 'paid'`, `planLevel: 'pro'`,
   `entitlements.pro.active == true` ; l'UI passe à « Votre offre actuelle » sur Pro.
3. Quotas serveur : dépasser le plafond Pro d'un quota borné (si le PO en définit un) →
   `resource-exhausted` avec le bon `errorCode`, et l'UI propose le palier minimal suffisant.
4. **Upgrade Pro → Ultra** via `change_plan` : facture Stripe prorata, `PRODUCT_CHANGE` reçu,
   `planLevel: 'ultra'` ; **Pro reste actif** dans la map jusqu'à son expiration ; palier
   effectif = Ultra.
5. **Downgrade Ultra → Pro** : vérifier le comportement réel de Stripe/RC et la date d'effet
   annoncée dans le dialog. **Écart entre l'annoncé et l'observé = bloquant.**
6. Résiliation (`cancel`) puis réactivation : inchangé, palier préservé.
7. Expiration (avancer l'horloge de test Stripe ou attendre) → `EXPIRATION` sur le dernier
   palier actif → `free`, `planLevel: null`, `proSince` **conservé**.
8. **Compte legacy** : créer un doc staging avec `subscriptionTier: 'paid'`,
   `proEntitlementActive: true`, **sans** `planLevel` ni `entitlements` (via console). Vérifier
   que l'UI affiche « Pro », que les quotas Pro s'appliquent, et qu'un event RC ultérieur
   matérialise la map sans rétrograder.
9. **Client ancien vs serveur neuf** : servir une build Flutter *pré-FEAT-056* contre le
   backend neuf, sur un compte `planLevel: 'ultra'` → doit rester pleinement fonctionnel
   (`paid` → illimité). C'est le test qui valide la décision §1.2 ; **s'il échoue, tout le
   plan est à revoir.**
10. Vérifier qu'un compte **de production** au hasard n'a **pas** été touché (auditer
    `updatedAt` sur `(default)` pendant la fenêtre de recette).

### 9.5 Rollback

| Étage | Procédure |
|---|---|
| Flutter | Revert de la PR + redeploy hosting. Le client ancien lit `paid` → accès conservé. |
| Functions | Redéploiement de la version précédente. `planLevel`/`entitlements` déjà écrits sont **ignorés** par l'ancien code ; `subscriptionTier` et `pro*` sont restés dans leur format d'origine → l'ancien webhook et l'ancien cron refonctionnent immédiatement. |
| Rules | Revert (les deux lignes de gel sont additives ; leur retrait ne casse rien). |
| Stripe / RevenueCat | **Ne rien supprimer.** Archiver les prix Max/Ultra (`active: false`) et retirer les produits des entitlements. Supprimer un entitlement casserait les abonnés qui l'ont déjà. |
| Données | **Aucune reprise nécessaire.** C'est le bénéfice direct de l'Option B — à mentionner en revue comme critère d'acceptation du design. |

Point d'attention : un abonné qui a acheté Ultra *avant* le rollback redevient, pour le code
ancien, un `paid` illimité — il conserve donc l'accès qu'il paie. Aucune perte pour le
client, un manque à gagner nul (il paie Ultra, il a « tout »). Le mode de défaillance est,
là encore, du bon côté.

---

## 10. Plan de tests

### 10.1 Dart (`test/unit`, `test/widget`)

| Fichier | Cas |
|---|---|
| `plan_matrix_parity_test.dart` **(nouveau, critique)** | lit `config/entitlements.json` du disque et compare à `plan_matrix.g.dart` : tous les paliers, tous les quotas, toutes les features, tous les rangs, tous les `errorCode` |
| `plan_level_test.dart` **(nouveau)** | `fromRaw('ultra', paid)` → ultra · `fromRaw('quantum', paid)` → **pro** (fail-UP, I4) · `fromRaw(null, paid)` → **pro** (I3) · `fromRaw('pro', free)` → **null** (I1) · `fromRaw(*, anonymous)` → null |
| `plan_entitlement_test.dart` **(nouveau)** | `atLeast` sur les 5 combinaisons de rang · `quota()` illimité vs borné · `has()` par `minLevel` · **jamais** de comparaison d'`index` d'enum |
| `subscription_tier_test.dart` (existant) | conserver `fromRaw('paid')` → `paid` et le fail-safe `anonymous` sur valeur inconnue de *tier* (ce fail-safe-là ne change pas) ; retirer les tests des 5 getters supprimés |
| `landlord_tier_snapshot_test.dart` (existant) | + `planLevel` présent / absent / inconnu |
| `pro_pricing_page_test.dart` (existant) | 3 cartes rendues · toggle mensuel/annuel · **rendu mobile (< 600) vs desktop (≥ 1024)** via `MediaQuery` forcée · état « offre actuelle » · CTA upgrade/downgrade selon le rang · `Env.subscriptionsEnabled == false` → 3× `_ComingSoonNotify` |
| `subscription_section_test.dart` (existant) | nom du palier · CTA « Changer d'offre » masqué pour `app_store`/`play_store` |
| `plan_change_controller_test.dart` **(nouveau)** | succès · `no_active_web_subscription` · `price_not_configured` · erreur générique |

### 10.2 Cloud Functions (`functions/src/__tests__`)

| Fichier | Cas |
|---|---|
| `plan_matrix_parity.test.ts` **(nouveau)** | symétrique du test Dart, même JSON |
| `plan.test.ts` **(nouveau)** | `resolvePlan` : `paid` sans `planLevel` → pro (I3) · tier absent → anonymous · `planLevel` inconnu → pro · `quotaLimit` illimité/borné/0 · `levelForRcEntitlement` : `"Bailan Pro"` → pro, inconnu → null (W5) |
| `derive_effective_plan.test.ts` **(nouveau, critique)** | aucun actif → free/null · un seul actif → ce palier · **deux actifs → max(rank)** (W3) · actif mais `expiresAt` passé → ignoré · `expiresAt == null` → considéré actif |
| `revenuecat_webhook.test.ts` (existant, à étendre) | `decideEntitlement` : **tous les cas existants doivent rester verts** · `INITIAL_PURCHASE ultra` sur compte free → paid/ultra · `EXPIRATION pro` sur compte **ultra actif** → **reste ultra** (W1) 🔴 · `EXPIRATION` du dernier palier → free + `planLevel: null` + `proSince` conservé (W6) · **arrivée désordonnée** : `INITIAL_PURCHASE ultra @T2` puis `EXPIRATION pro @T1` → ultra conservé, pro inactif (W2) 🔴 · rejeu du même event → aucun changement (W7) · entitlement inconnu → `ignored` (W5) · `$RCAnonymousID:*` → `ignored` · `isAnonymous: true` → `ignored` · **doc legacy sans map** → matérialisée via `legacyStates`, pas de rétrogradation (§3.4) 🔴 · `PRODUCT_CHANGE pro→ultra` → ultra |
| `reconcile_entitlements.test.ts` (existant, à étendre) | `free` + RC actif → **`unchanged`** (invariant maintenu) 🔴 · `paid/pro` + RC ultra → `level_changed` · `paid/ultra` + RC pro seul → `level_changed` (pas `downgraded_free`) · `paid` + RC vide → `downgraded_free` + `planLevel: null` · échéance repoussée → `renewed` · fetcher qui throw → `failed`, les autres comptes traités |
| `create_checkout_session.test.ts` (existant, à étendre) | **`{plan:'annual'}` legacy → level pro / period annual** (rétrocompat) 🔴 · `{level:'ultra',period:'monthly'}` → bon price · level inconnu → `invalid-argument` · **palier `purchasable: false` → `level_not_purchasable`, vérifié AVANT le price** 🔴 · price non configuré → `failed-precondition/price_not_configured` · `rc_app_user_id` présent sur **session ET** `subscription_data` (test existant à préserver) · déjà abonné → `already_subscribed_use_change_plan` |
| `manage_subscription.test.ts` (existant, à étendre) | `parseAction('change_plan')` OK · `pickManageableSubscription` inchangé · même price cible → `noop` **sans appel Stripe** · pas d'abonnement web → `no_active_web_subscription` · `assertSafeUid` inchangé |
| `property_tenant.test.ts`, `lease_payment.test.ts`, `documents.test.ts` (existants) | **tous les cas free doivent rester identiques** (non-régression du freemium) + un cas par palier payant avec un quota borné + codes d'erreur inchangés |
| `documents.test.ts` (taille, nouveau bloc) | free/pro 10 Mio accepté, 10 Mio + 1 refusé · max : 25 Mio accepté, 26 refusé · ultra : 50 Mio accepté · l'erreur `file_too_large` **nomme le palier minimal suffisant** (`minLevelForQuota`) 🔴 · un fichier > 50 Mio ne propose **aucun** palier (message générique, pas d'upsell mensonger) |
| `plan_matrix` (via `plan.test.ts`) | `hasFeature(ultra, 'accountingExport')` → **`false`** tant que `status: 'planned'` 🔴 · `isPurchasable('max')` → `false` au lancement |
| `rental_register_free_e2e.test.ts` (existant) | doit passer **sans modification** — c'est le test de non-régression le plus parlant |

🔴 = cas dont l'absence rendrait la PR non-mergeable.

### 10.3 Règles Firestore (`functions/rules-tests/firestore_rules.test.ts`, `npm run test:rules`)

| Cas |
|---|
| update client qui tente d'écrire `planLevel: 'ultra'` sur son propre doc → **DENY** |
| update client qui tente de modifier `entitlements` → **DENY** |
| update client légitime (téléphone/adresse) sur un doc **portant** `planLevel` → **ALLOW** (non-régression : un doc payant doit rester éditable) |
| update client légitime sur un doc **sans** `planLevel` (legacy) → **ALLOW** (le `.get(…, null)` doit tolérer l'absence) |
| create de compte avec `planLevel` non nul → **DENY** |
| create de compte avec `entitlements` → **DENY** |
| create anonyme avec `planLevel` → **DENY** |
| cross-user : lire/écrire le `planLevel` d'un autre uid → **DENY** |
| les 16 cas existants restent verts |

### 10.4 Cas limites à couvrir absolument

1. Doc legacy `paid` sans `planLevel` ni `entitlements` (le plus fréquent en prod).
2. Deux entitlements actifs simultanément (chevauchement de downgrade différé).
3. Events RevenueCat arrivés dans le désordre, sur **deux paliers différents**.
4. Client Flutter antérieur face à un `planLevel` qu'il ne connaît pas.
5. Price Stripe non configuré pour un palier (état permanent de la prod pendant des semaines).
6. Abonné mobile (`proStore != 'web'`) demandant un `change_plan`.
7. Rejeu intégral d'un lot d'events (RevenueCat retente sur 5xx).
8. Compte anonyme portant un event RC (doit être ignoré, jamais de doc anonyme payant).
9. Appel direct à `createCheckoutSession` sur un palier affiché mais non vendable (Max/Ultra
   au lancement) — l'UI ne l'offre pas, le serveur doit quand même refuser.
10. Feature `status: 'planned'` interrogée depuis le palier le plus élevé (Ultra) → `false`.
11. Fichier plus gros que le plafond du palier **le plus élevé** → refus sans upsell.

---

## 11. Découpage en PRs

Chaque lot est mergeable et révisable seul, et laisse `develop` déployable.

| PR | Titre | Périmètre fichiers | Critère de sortie |
|---|---|---|---|
| **PR-1** | `chore(entitlements): table de config unique + génération + garde CI` | `config/entitlements.json` (valeurs **actuelles** reportées à l'identique, Max/Ultra = copie de Pro en attendant le PO) · `tool/gen_entitlements.dart` · `functions/tool/gen_entitlements.mjs` · `scripts/check-entitlements-parity.sh` · `.github/workflows/*` · les 2 fichiers générés · 2 tests de parité | CI verte, `check-entitlements-parity.sh` échoue si on édite un fichier généré à la main. **Aucun comportement produit modifié.** |
| **PR-2** | `refactor(functions): gating par la table, zéro constante en dur` | `property_tenant.ts` · `lease_payment.ts` · `documents.ts` · nouveau `functions/src/entitlements/plan.ts` · tests associés | Tous les tests Functions existants verts **sans modification de leurs assertions free**. `rental_register_free_e2e` vert. Refactor pur. |
| **PR-2b** *(conditionnelle)* | `feat(functions): callable createScenario + quota serveur` | `functions/src/callable/scenarios.ts` · `index.ts` · `firestore.rules` (`investment_scenarios/create` → `false`) · repo/contrôleur Dart · tests | Ne partir que si le PO différencie les scénarios entre paliers. Sinon, dette documentée. |
| **PR-3** | `feat(functions): entitlements multi-paliers (webhook + cron)` | `revenuecat_webhook.ts` · `reconcile_entitlements.ts` · `plan.ts` (`deriveEffectivePlan`, `legacyStates`) · `firestore.rules` (+ 6 lignes) · `firestore.indexes.json` (fieldOverride optionnel) · tests webhook/cron/rules | Tous les cas 🔴 de §10.2 verts. Rétrocompat legacy prouvée par test. Rules déployées par la CI. |
| **PR-4** | `feat(functions): checkout 3 paliers + changement d'offre` | `create_checkout_session.ts` (+ shim legacy) · `manage_subscription.ts` (`change_plan`) · params `STRIPE_PRICE_*` · tests | `{plan}` legacy toujours accepté (test dédié). `price_not_configured` couvert. `already_subscribed_use_change_plan` couvert. |
| **PR-5** | `feat(app): modèle de palier Dart + migration des gates` | `plan_level.dart` · `plan_entitlement.dart` · `landlord_tier_repository.dart` · `subscription_tier.dart` (retrait des getters) · les ~10 fichiers UI qui comparaient `== SubscriptionTier.paid` · providers · tests unitaires | `flutter analyze` clean, zéro `== SubscriptionTier.paid` résiduel hors `plan_entitlement.dart`, tests de parité verts. **Aucun changement visuel** (Max/Ultra encore identiques à Pro dans la table). |
| **PR-6** | `feat(app): page /pro 3 offres + badges + i18n` | `pro_pricing_page.dart` · `plan_card.dart` · `plan_comparison_table.dart` · `pro_badge.dart` · `tier_chip.dart` · `subscription_section.dart` · `plan_change_controller/repository` · `pro_success_page.dart` · `app_fr.arb` + `app_en.arb` · tests widget responsive | Recette staging §9.4 items 1-9 OK. Responsive validé aux 3 breakpoints. FR **et** EN complets (aucune clé manquante). |
| **PR-7** | `chore: remplir la grille commerciale (grille PO §2/§4)` | `config/entitlements.json` **uniquement** (+ régénération) · quotas, prix indicatifs, `purchasable`, features `planned` | **Une PR d'un seul fichier de données** : c'est le test ultime que l'architecture est bien paramétrable. Peut être fusionnée dans PR-1 puisque la grille PO est déjà livrée — la garder séparée reste préférable pour isoler la revue *technique* de la revue *commerciale*. |
| **PR-7b** | `feat(functions+app): quota de taille de fichier par palier` | `documents.ts` (`MAX_BYTES` → `documentMaxBytes`) · erreur `file_too_large` + upsell contextuel · pré-vérification UI · i18n · tests | = user story **FEAT-056d** du PO. Le seul quota différenciant *réellement construit* au lancement : à traiter à part, il touche un chemin d'upload testé. |
| **PR-7c** *(à l'ouverture de Max, puis d'Ultra)* | `chore: ouvrir le palier <level> à la vente` | `config/entitlements.json` (`purchasable: true`, `priceIndicative: false`) + prix Stripe + entitlement RC | = user stories **FEAT-056f / FEAT-056g**. **Zéro ligne de Dart ou de TypeScript** — si cette PR nécessite du code, la paramétrisation a échoué. |
| **PR-8** *(différée)* | `chore(functions): retrait du shim {plan} legacy` | `create_checkout_session.ts` · test | À n'ouvrir qu'une fois une version plancher mobile effectivement diffusée. |

**Effort estimé** (dev seul, hors config dashboard Stripe/RevenueCat et hors rédaction PO) :

| PR | Estimation |
|---|---|
| PR-1 | 0,5 j |
| PR-2 | 0,5 j |
| PR-2b (conditionnelle) | 1 j |
| PR-3 | 1,5 j (le cœur du risque) |
| PR-4 | 1 j |
| PR-5 | 0,5 j |
| PR-6 | 1,5 j |
| PR-7 | 0,25 j |
| PR-7b (quota taille fichier) | 0,5 j |
| PR-7c (ouverture d'un palier) | 0,1 j × palier, plus tard |
| Recette staging §9.4 | 0,5 j |
| **Total** | **~6,75 j** (7,75 j avec PR-2b) |

---

## Risks

| # | Risque | Gravité | Mitigation |
|---|---|---|---|
| **R1** | **Divergence client/serveur sur la grille** — le client autorise ce que le serveur refuse (ou l'inverse) | Élevée (support + churn) | Table unique + génération + `check-entitlements-parity.sh` en CI + 2 tests de parité runtime (§2.2). Le serveur reste **la** source de vérité ; l'UI n'est qu'un miroir. |
| **R2** | **Palier effectif faux sur chevauchement d'entitlements** — on facture Ultra et on sert Pro | **Critique (argent réel)** | Map d'état par palier, garde d'ordre par palier, `deriveEffectivePlan` unique partagée webhook + cron, cas 🔴 obligatoires en test (§10.2). |
| **R3** | **Politique de proration non validée** — le downgrade immédiat avec avoir peut ne pas être la volonté produit | Moyenne (litiges, avis) | ⚠️ **Décision PO requise avant PR-4.** Deux options chiffrées : immédiat+prorata (retenu par défaut, simple) vs différé fin de période (Subscription Schedules, +1 j). Dans les deux cas, l'UI doit annoncer l'effet **avant** confirmation. |
| **R4** | **Renommage de l'entitlement `"Bailan Pro"`** (typo tentante) | **Critique** | La chaîne est gelée dans `config/entitlements.json` avec un commentaire ; un renommage RC ferait ignorer silencieusement tous les events des abonnés existants (plus d'expiration, plus de renouvellement). |
| **R5** | **Déploiement Functions partagé prod/staging** | Élevée | Design inerte par défaut : `subscriptionTier` reste `paid`, `legacyStates` évite toute migration, `price_not_configured` bloque les paliers non configurés, entitlements RC inexistants → aucun event. Test §9.4-9 (client ancien / serveur neuf) obligatoire. |
| **R6** | **Test staging qui écrit en prod** via `dbForLandlordUid` (prod-first) | Élevée | Protocole uid-neuf §9.3, vérification préalable de non-existence dans `(default)`, audit `updatedAt` prod après recette. |
| **R7** | **Quotas non enforcés serveur** (scénarios, régularisation, comparaison) deviennent des différenciateurs contournables | Moyenne | `enforcement` déclaré dans la table (visible en revue) ; PR-2b ferme le cas scénarios si le PO en fait un différenciateur. |
| **R8** | **Prix affiché ≠ prix Stripe** (les prix sont en dur dans l'UI aujourd'hui) | Moyenne (juridique : prix annoncé) | Prix dans la table de config + case de QA manuelle au lancement. Pas de vérification automatique possible sans exposer l'API Stripe au client (exclu). |
| **R9** | **Double abonnement** si un abonné actif repasse par Checkout | Élevée (remboursements) | Garde serveur `already_subscribed_use_change_plan` **et** UI qui n'expose jamais « S'abonner » à un abonné actif. Défense en profondeur : le serveur doit refuser même si l'UI se trompe. |
| **R10** | **Explosion du coût du cron** quand la base grandit (réconciliation de tous les actifs) | Faible | Ensemble borné par la base d'abonnés ; `limit` 200 conservé ; pagination par curseur documentée comme dette dans le code. |
| **R11** | **Clé Stripe `sk_test_` partagée** — passage en live hors périmètre (issue #138) | Bloquant commercial, pas technique | Rappel explicite : FEAT-056 se valide **entièrement en test mode**. Aucune ouverture prod sans #138. |
| **R12** | **Vendre un palier dont les features distinctives n'existent pas** (Max sans FEAT-031/051, Ultra sans FEAT-032/034) | Élevée (juridique : pratique commerciale trompeuse ; avis stores) | `purchasable: false` **côté serveur** (`level_not_purchasable`) et pas seulement côté UI ; `status: 'planned'` → `hasFeature()` renvoie `false` même pour Ultra. L'ouverture est une PR de config, tracée, subordonnée à la livraison du chantier métier (PR-7c). |
| **R13** | **Refus d'upload sans issue** — un compte Pro qui scanne un bail de 30 Mio se heurte à un mur | Moyenne (frustration, support) | L'erreur `file_too_large` nomme le palier minimal suffisant (`minLevelForQuota`) ; pré-vérification côté UI **avant** l'upload pour ne pas consommer la bande passante. Ne jamais renvoyer un `invalid-argument` nu. |

---

## Step-by-step execution order

1. **PR-1** — table de config + générateurs + `scripts/check-entitlements-parity.sh` en CI (aucun changement produit).
2. **PR-2** — refactor du gating serveur vers la table (`property_tenant`, `lease_payment`, `documents`) ; tous les tests free inchangés et verts.
3. *(conditionnel)* **PR-2b** — callable `createScenario` + `firestore.rules` (`investment_scenarios/create` → `false`).
4. **PR-3** — `firestore.rules` (+ gel `planLevel`/`entitlements`) et `firestore.indexes.json`, puis webhook + cron multi-paliers. Rules déployées **automatiquement par la CI** (`develop` → base `staging`).
5. **PR-4** — `createCheckoutSession` 3×2 + shim legacy `{plan}` + `manageSubscription(change_plan)`.
6. **Déploiement manuel des Cloud Functions** (hors CI, délibéré) — après revue `code-reviewer` + `security-auditor`, et **avec confirmation utilisateur explicite** puisque le déploiement est partagé avec la prod.
7. Configuration dashboard **RevenueCat** (2 entitlements) puis **Stripe test mode** (4 prix) + params `STRIPE_PRICE_{MAX,ULTRA}_{MONTHLY,ANNUAL}`.
8. **PR-5** — modèle Dart (`PlanLevel`, `PlanEntitlement`) et migration des gates UI, sans changement visuel.
9. **PR-6** — page `/pro` 3 offres (responsive FEAT-055), badges, section profil, i18n FR+EN.
10. **Recette staging** §9.4 (10 scénarios, dont le test « client ancien / serveur neuf » et l'audit de non-contamination prod).
11. **PR-7** — remplissage de la grille commerciale (grille PO §2/§4) : un seul fichier JSON.
    Puis **PR-7b** — quota de taille de fichier par palier (FEAT-056d), seul quota
    différenciant réellement construit au lancement.
12. `qa-tester`, puis `code-reviewer` + `security-auditor` sur l'ensemble.
13. **`state-keeper`** sur `docs/state/{schema,functions}/account.md` **uniquement** — en corrigeant au passage les deux dérives constatées (§0 : `manage_subscription.ts` absent, routes `/pro/success|cancel` déclarées inexistantes alors qu'elles existent).
14. Merge `develop` → `main` : prod reste fermée (`SUBSCRIPTIONS_ENABLED=false`). L'ouverture commerciale est une décision distincte, subordonnée à l'issue #138 (clé Stripe live).
15. *(plus tard, hors FEAT-056)* **PR-7c** — ouverture de Max puis d'Ultra à la vente, une
    fois leurs features distinctives livrées (FEAT-031/051 pour Max, FEAT-032/034 pour
    Ultra) : basculer `purchasable`/`priceIndicative` dans le JSON, créer les prix Stripe et
    les entitlements RevenueCat. **Aucune ligne de code applicatif** — c'est le critère qui
    valide, a posteriori, que l'architecture de ce plan était bien paramétrable.
