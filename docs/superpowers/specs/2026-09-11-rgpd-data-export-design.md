# FEAT-047 — Export des données RGPD (accès + portabilité)

> Spec de conception — 2026-09-11
> Statut : validée par le propriétaire (design approuvé), prête pour le plan.
> Suivi de l'audit FEAT-045 : `docs/LEGAL.md:28` promet déjà « exporter ses
> données (`GET /export`) » ; cette spec l'honore. Non gaté par la
> micro-entreprise (pré-lancement).

## 1. Contexte et problème

Le RGPD ouvre au bailleur un **droit d'accès** (art. 15 — obtenir une copie de
ses données) et un **droit à la portabilité** (art. 20 — les recevoir dans un
format structuré, couramment utilisé, lisible par machine). L'app promet déjà
l'export dans sa privacy policy mais ne le fournit pas. La suppression de compte
(`deleteAccount`, FEAT-045) parcourt déjà toutes les collections du bailleur ;
l'export est le **même parcours, en lecture**.

## 2. Objectif

Permettre au bailleur d'exporter **toutes ses données** en un JSON structuré
unique, à la demande, depuis l'écran Profil, sur web et mobile.

## 3. État actuel (référence)

- `functions/src/callable/delete_account.ts` énumère les collections du bailleur
  par `landlordId == uid` : `properties, tenants, leases, payments, documents,
  expenses, investment_scenarios, support_requests` (constante
  `PURGED_COLLECTIONS`), traite `receipts` à part (rétention légale), et les
  singletons `landlords/{uid}` + `paid_plan_interest/{uid}`. Il utilise
  `dbForRequest(request)` (isolation d'environnement, ADR 0003) et
  `requireAuthUid`, avec une **garde d'auth récente (< 5 min,
  `RECENT_AUTH_MAX_AGE_SECONDS`)** pour les comptes non-anonymes (anonymes
  exemptés, état confirmé via Admin SDK `providerData`).
- Accès Firestore jamais en direct : Functions via `dbForRequest` ; client via
  `firestoreProvider`. `admin.firestore()` interdit hors routeur.
- Le partage de fichier client existe déjà (partage de quittance : Web Share API
  / partage natif) — mécanisme réutilisable pour livrer le fichier d'export.

## 4. Décisions (2026-09-11)

| Point | Décision |
|---|---|
| Format | **JSON structuré unique** (machine-readable, art. 20). Pas de CSV, pas de zip. |
| Livraison | **Réponse callable inline** : la callable renvoie le JSON ; le client l'écrit dans un fichier et le propose au téléchargement (web) / partage natif (mobile). Aucun objet Storage. |
| Fichiers binaires | **Référencés** (chemin Storage / URL de téléchargement présents dans le JSON), **non empaquetés**. Ils restent téléchargeables un par un dans l'app. |
| Collections | Toutes celles du bailleur : `properties, tenants, leases, payments, receipts, documents, expenses, investment_scenarios, support_requests` + singletons `landlords/{uid}` (profil) et `paid_plan_interest/{uid}`. **`receipts` incluses** (données du bailleur, art. 15). |
| Enregistrements soft-deleted | **Inclus** (avec leur `deletedAt`) — transparence complète sur les données détenues (dont quittances retenues 5 ans). |
| Garde d'auth récente | **Conservée** (< 5 min) pour comptes non-anonymes — exporter toutes les PII mérite la même protection qu'une suppression. Anonymes exemptés (même logique que `deleteAccount`). |
| Emplacement client | Tuile **« Exporter mes données »** dans l'écran Profil (section compte/confidentialité). |
| Nom de fichier | `baillan-export-AAAA-MM-JJ.json`. |

## 5. Composants

### 5.1 Callable serveur — `exportAccountData`
`functions/src/callable/export_account_data.ts`, région `europe-west1`,
enregistrée dans `functions/src/index.ts`.

- `requireAuthUid(request)` + garde d'auth récente (réutiliser la même logique
  que `deleteAccount` : token `auth_time` < `RECENT_AUTH_MAX_AGE_SECONDS`, sauf
  compte anonyme confirmé via `admin.auth().getUser(uid).providerData.length === 0`).
  Extraire cette garde dans un helper partagé si cela évite la duplication (au
  jugement de l'implémenteur ; sinon la répéter est acceptable).
- `const db = dbForRequest(request);`
- Lit chaque collection par `db.collection(<name>).where("landlordId", "==", uid).get()`,
  mappe chaque doc en `{ id, ...data }` avec les `Timestamp` convertis en
  chaînes ISO 8601 (UTC). Lit les singletons `landlords/{uid}` et
  `paid_plan_interest/{uid}` (peuvent être absents → `null`).
- Assemble et retourne :
  ```
  {
    "exportedAt": "<ISO now>",
    "schemaVersion": 1,
    "account": { ...landlords/{uid} } | null,
    "paidPlanInterest": { ...paid_plan_interest/{uid} } | null,
    "properties": [ { id, ... }, ... ],
    "tenants": [ ... ],
    "leases": [ ... ],
    "payments": [ ... ],
    "receipts": [ ... ],
    "documents": [ ... ],
    "expenses": [ ... ],
    "investmentScenarios": [ ... ],   // collection investment_scenarios
    "supportRequests": [ ... ]        // collection support_requests
  }
  ```
- Pas de pagination nécessaire pour un bailleur typique ; lecture simple par
  collection (les volumes restent sous la limite de réponse callable ~10 Mo).
  `timeoutSeconds` généreux (ex. 120).

### 5.2 Client — repository + provider
- Une méthode client (repository/service compte) appelant la callable
  `exportAccountData` et renvoyant la Map JSON.
- Un contrôleur/provider Riverpod portant l'état `idle / loading / success /
  error` de l'export (analogie avec le contrôleur de partage de quittance).

### 5.3 Client — UI Profil
- Tuile **« Exporter mes données »** dans l'écran Profil (section
  compte/confidentialité), avec sous-texte court (« Recevez une copie de vos
  données au format JSON »).
- Au tap : déclenche l'export ; spinner pendant l'appel ; au succès, sérialise
  le JSON dans un fichier `baillan-export-AAAA-MM-JJ.json` et le remet à
  l'utilisateur via le **mécanisme de partage/téléchargement existant** (web :
  téléchargement ; mobile : partage natif). En cas d'erreur : message non
  bloquant + possibilité de réessayer.
- Si la garde d'auth récente rejette (token trop vieux), afficher un message
  invitant à se reconnecter puis réessayer (même famille d'erreur que le
  `requires-recent-login` de la suppression de compte).

## 6. Contraintes

- **Accès Firestore jamais en direct** : Functions via `dbForRequest` ; aucun
  `admin.firestore()`. Client via les providers/callable, jamais
  `FirebaseFirestore.instance`.
- **Isolation cross-user** : l'export ne renvoie **que** les données dont
  `landlordId == uid` (et les singletons de cet uid). Ne jamais renvoyer les
  données d'un autre bailleur — testé explicitement.
- **Isolation d'environnement** (ADR 0003) : `dbForRequest` sélectionne la base
  selon `APP_ENV` de la requête.
- **i18n** FR + EN pour tous les libellés client.
- Jetons de design uniquement côté UI ; aucune couleur en dur.

## 7. Vérification

- **Functions** (`export_account_data.test.ts`, émulateur / fake) :
  - renvoie un objet contenant toutes les clés de collections + `account` ;
  - un bailleur avec des biens/baux/paiements les retrouve dans l'export ;
  - **cross-user** : les documents d'un AUTRE `landlordId` ne figurent PAS dans
    l'export de l'uid ;
  - singletons absents → `account`/`paidPlanInterest` à `null`, pas d'erreur ;
  - garde d'auth récente : token non-anonyme trop vieux → rejet ; anonyme →
    exempté ; token récent → succès ;
  - les `Timestamp` sont sérialisés en chaînes ISO.
- **Flutter** :
  - contrôleur : succès (callable renvoie une Map → état success + fichier
    produit), erreur (callable throw → état error) ;
  - widget : la tuile Profil « Exporter mes données » existe, déclenche
    l'export, montre le spinner puis délègue au partage/téléchargement.
- `flutter analyze` clean ; `dart format` clean (repo-wide) ; suite Flutter +
  suite Functions vertes.

## 8. Hors périmètre

- CSV, zip, empaquetage des fichiers binaires (référencés seulement).
- Livraison par URL signée / objet Storage (réponse inline retenue).
- Export asynchrone / planifié / notifié par email.
- Pagination avancée (volumes attendus faibles ; à revoir si un compte dépasse
  la limite de réponse callable).
- Purge/rétention d'artefacts d'export (aucun objet stocké côté serveur).
