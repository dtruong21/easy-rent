# Historique des changements (état projet)

> **Fichier d'archive — NE PAS auto-charger.** Sorti de `INDEX.md` (diète tokens
> 2026-07-09) pour que le routeur d'état reste léger. À consulter uniquement
> pour l'historique détaillé d'une feature. Le statut courant vit dans
> [`FEATURES.md`](FEATURES.md) (matrice) ; les détails techniques dans les shards
> `schema/`, `functions/`, `routes/`.

## Changements (2026-07-23 → 2026-07-30)

### PR #145 : FEAT-054 — ADR 0003 — isolation Firestore prod/staging implémentée (2026-07-25)
- Base Firestore nommée `staging` déclarée (`firebase.json`), séparée de `(default)` prod.
- Flutter : `firestoreProvider` (`lib/core/config/firestore_provider.dart`) route vers `staging` (web staging uniquement) vs `(default)` (fail-safe pour émulateur + prod + mobile).
- Backend : helper `dbForRequest(request)` route par en-tête `Origin` (callables), `dbForLandlordUid(uid)` route webhook RevenueCat par présence du doc landlord (fail-safe prod d'abord).
- CI check `scripts/check-db-isolation.sh` : interdit `FirebaseFirestore.instance` hors provider/main.dart, et `admin.firestore()`/`getFirestore()` hors du routing.
- État : ✅ les shards `functions/account.md` et `functions/README.md` mis à jour pour documenter les patterns ADR 0003.

### PR #148, #151 : FEAT-055 — Comparaison de scénarios de simulation, entrée visible + responsive (2026-07-24, 2026-07-27)
- Route `/simulator/compare` (query param `ids=`), page `ScenarioComparisonPage`.
- Responsive mobile (cartes) + desktop (table fluide).
- Feature gate : logique Pro intégrée dans la page, route pas encore gâtée (✅ ticket d'audit : FEAT-055 à terminer côté gate).
- État : ✅ statut FEATURES.md passé de `💡 idea` → `✅ done` ; route documentée dans `routes/simulator.md`.

### PR #152 : CI — déploiement de rules+indexes par base Firestore (2026-07-30)
- `firebase deploy --only firestore` déploie maintenant les deux bases `(default)` et `staging` correctement.
- Cloud Functions restent hors CI (déploiement manuel délibéré).
- Impact code : zéro ; pur workflow.

## Changements (2026-07-03 → 2026-07-21)

### PR #128 : `docs/SECURITY.md` réaligné sur la stack Firebase réelle — DOC (2026-07-21)
- Suite de **PR #127**. Point de départ vérifié : **Supabase a totalement disparu du dépôt** (aucune dépendance `supabase_flutter`, aucun dossier `supabase/`, aucune migration SQL) — la réécriture s'est donc faite sur inventaire, pas par renommage.
- **La table des secrets était incomplète** — c'est le point le plus sérieux. La section « ❌ Secrètes » listait `sb_secret_*` / `service_role` (inexistants) et **omettait tous les secrets réellement en place** : `STRIPE_SECRET_KEY`, `REVENUECAT_API_KEY`, `REVENUECAT_WEBHOOK_AUTH` (relevés via `defineSecret` dans `functions/src/`). Le document censé recenser les secrets ne mentionnait pas les clés de paiement.
- **App Check présenté comme une protection active** alors qu'il n'est **pas activé** (aucun package `firebase_app_check`, aucune activation — seul un pod interop transitif dans `ios/Podfile.lock`). Seules les règles Firestore protègent la config Firebase publique.
- Secrets CI : la liste annoncée (`SUPABASE_URL_PROD`, `SUPABASE_ANON_KEY_PROD`, `FIREBASE_SERVICE_ACCOUNT_PROD`) ne correspondait à aucun secret réel → remplacée par la liste relevée dans `.github/workflows/` (`FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID`, `CLAUDE_CODE_OAUTH_TOKEN`, `GITHUB_TOKEN`).
- Rotation : procédures `supabase secrets set` → Secret Manager (Stripe/RevenueCat) + GCP IAM (service account). Avertissement ajouté : `REVENUECAT_WEBHOOK_AUTH` doit être tourné **des deux côtés**, un décalage rejette les webhooks et désynchronise les entitlements (panne silencieuse côté facturation).
- Section « flag GUC `app.*` » marquée **obsolète** (footgun PostgREST sur une base qui n'existe plus), conservée comme repère plutôt que supprimée. Le « hardening P1 » associé dans `docs/BACKLOG.md` est sans objet.
- Corrigé aussi : le doc affirmait que le changement de mot de passe in-app n'existait pas (« à ajouter FEAT-012 ») — il est livré depuis **FEAT-025** (`reauthenticateWithPassword` + `updatePassword`).
- **Suites ouvertes** : #130 (revue `security-auditor` — confirmer la complétude de l'inventaire côté consoles, invisible depuis le code) et #131 (angles morts de `scripts/check-secrets.sh` : aucun pattern RevenueCat, pas de `sk_test_`/`whsec_`, `SECURITY.md` exclu du scan). Le script **n'a pas été modifié** : changer un filet de sécurité mérite sa propre revue.

### PR #127 : `docs/SECURITY.md` — persistance de session et politique mot de passe (post-FEAT-019) — DOC (2026-07-21)
- La section « Politique mot de passe » datait d'avant le pivot FEAT-019 et décrivait `supabase_flutter`. Deux affirmations **fausses**, pas seulement périmées :
  - **Stockage** : pas localStorage. Aucun `setPersistence` dans `lib/` → persistance par défaut de `firebase_auth_web` 5.15.3, chaîne `indexedDBLocalPersistence` → `browserLocalPersistence` → `browserSessionPersistence` (`getAuthInstance`, `interop/auth.dart`). C'est **IndexedDB** ; localStorage n'est qu'un repli.
  - **Durée de vie** : la session n'est **pas** perdue à la fermeture du navigateur, elle y survit. Fin uniquement sur `signOut()`, suppression de compte, ou révocation de jeton.
- **Note RGPD « pas de remember me » = engagement fantôme.** La contrainte a été révisée le **2026-05-27** (décision figée, `docs/backlog/001-auth-magic-link.md`) : persistance standard conservée, pas de bascule UI, base légale à documenter dans la politique de confidentialité — obligation **déjà satisfaite** par le §7 « Cookies et traceurs » (`privacy_page.dart`), qui décrit correctement IndexedDB. `SECURITY.md` affichait donc une posture plus stricte que celle réellement tenue.
- **La règle de mot de passe n'est pas appliquée côté serveur** : les 8 car. + lettre + chiffre vivent dans `PasswordValidator` (`lib/core/utils/password_validator.dart`), **côté client uniquement**. Aucune password policy Firebase/Identity Platform n'est configurée → plancher serveur réel = `weak-password` natif à **6 caractères**, sans contrainte de composition. Documenté en encadré ⚠️ plutôt que masqué par « built-in ».
- Rate limiting : le « 3 tentatives/minute » était un chiffre Supabase. Firebase ne publie pas ses seuils → **chiffre retiré sans être remplacé**, description du mécanisme réel à la place (`too-many-requests` → `AuthError.tooManyRequests`).
- Archives `docs/plans/FEAT-*.md` et `docs/backlog/*.md` **non touchées** (mentions Supabase légitimes et datées).

### PR #126 : Version + environnement en pied de la page de garde — FEAT (2026-07-21)
- Distingue prod et staging d'un coup d'œil sans ouvrir le Profil — utile depuis que les deux ont un vrai domaine (`baillan.com` / `stage.baillan.com`).
- Réutilise **exactement** les mêmes sources que « Profil → À propos » (`appInfoProvider` + `Env.isProd` + clés l10n existantes) : une seule vérité sur la version, aucune nouvelle chaîne à traduire.
- Rendu volontairement asymétrique : hors prod, pastille d'environnement visible (tout l'intérêt) ; en prod, version seule et discrète — afficher « production » à de vrais utilisateurs serait du bruit, l'absence de pastille suffit.
- Si la version n'est pas encore chargée : on n'affiche **rien** plutôt qu'un placeholder (évite un saut de mise en page sur la 1re vue).
- `ConsumerWidget` dédié plutôt que conversion de `LandingSheet` (`StatelessWidget`) → diff minimal sur un fichier de design sensible. 3 tests ; suite 2508.

### PR #125 : Commentaire d'en-tête d'`env.dart` — DOC (2026-07-21)
- Le doc comment affirmait que la séparation prod/dev passe par « `(default)` vs `dev` Firestore database ». **Ce n'est pas implémenté** : les 21 accès Firestore de `lib/` utilisent `FirebaseFirestore.instance` (base `(default)`), aucun `instanceFor(databaseId:)` ; `firebase.json` ne déclare que `"database": "(default)"`.
- **Conséquence à retenir** : staging et prod partagent Firestore, Auth, Storage et Functions du projet `easy-rent-54cd4`. L'isolation est au niveau **Hosting uniquement** (deux sites). **Un test sur staging écrit en PRODUCTION.** Le seul environnement réellement isolé est l'émulateur (`Env.useFirebaseEmulator`).
- Commentaire uniquement — aucun changement de comportement.

### PR #124 : Staging sur son propre site Hosting → `stage.baillan.com` — CI (2026-07-21)
- Hosting passe en multi-site : deux cibles `prod` et `stage` dans `firebase.json` (au lieu d'un channel de prévisualisation).
- Ne change **pas** l'isolation des données : voir #125 — staging et prod partagent le même projet Firebase.

### PR #123 : `CONVENTIONS.md` + `ENVIRONMENTS.md` alignés sur Firebase, préfixe `feat/` — DOC (2026-07-21)
- `CONVENTIONS.md` décrivait encore Supabase alors que le pivot FEAT-019 (2026-06-30) a migré le backend vers Firestore : les agents lisant ce fichier étaient orientés vers le **mauvais backend**.
- Réécrit : camelCase, montants en centimes, helpers `firestore.rules`, soft-delete via `softDeleteEntity`, immutables, index composites ; renvoie vers `docs/state/schema/` comme source de vérité.
- Souligne la règle `allow list` + `where('landlordId','==',uid)` (audit FEAT-045 H1) : **les rules ne sont pas des filtres**.
- Arborescence : retire `supabase/`, ajoute `functions/`, `android/`, `ios/`, `assets/`, `tool/`. Tests : `test/integration/` (et non `integration_test/`), `npm test` (CF), `npm run test:rules` (règles).
- Nouvelle section Cloud Storage CLI : `gcloud storage`, **jamais `gsutil`** (retrait du bundle gcloud en mars 2027).
- Préfixe de branche standardisé sur `feat/` (`CONVENTIONS.md` disait `feat/`, `GITFLOW.md` disait `feature/`). Git : PR vers `develop`, jamais `main`.

### PR #121 : Domaine canonique `baillan.com` — FEAT/SEO (2026-07-21)
- Bascule toutes les URL **publiques** de l'URL intérimaire `.web.app` vers l'apex : `web/index.html` (canonical, og:url, og:image, twitter:image, 3 URLs JSON-LD + logo — 8 occurrences), `web/sitemap.xml` (5 `<loc>`), `web/robots.txt` (Sitemap), `Env.publicAppUrl`, et le défaut `WEB_APP_BASE_URL` de `create_checkout_session.ts` (redirections Stripe success/cancel).
- ⚠️ **Les identifiants du PROJET Firebase restent inchangés à dessein** : `projectId`/`authDomain`/`storageBucket` (`easy-rent-54cd4*`) ne sont pas le domaine public — les remplacer casserait auth/Firestore/Storage.
- Reste-à-faire côté consoles documenté dans `docs/SEO.md` (Hosting apex + www en redirection, DNS, SSL, domaines autorisés Firebase Auth, URL `/delete-account` sur la fiche Play).

### PR #120 : Gating Pro — quota documents (#29) + régularisation des charges (#28) — FEAT (2026-07-20)
- Applique la matrice free/Pro validée le 2026-07-20.
- **Quota documents — enforcement SERVEUR** (ressource réelle à protéger) : `SubscriptionTier.documentLimit` = anonyme 0 / free **10** / paid illimité. `createDocument` gate **AVANT** tout travail coûteux (lookups cross-entity + Storage) → `resource-exhausted` / `document_limit_reached`.
- **Comptage LIVE** plutôt qu'un compteur dénormalisé : le volume est borné et le soft-delete est universel — sans compteur, **aucune dérive possible** (rien à décrémenter). 7 tests dont : soft-deleted non comptés, docs d'un autre landlord non comptés, landlord absent → `not-found` (fail-closed).
- **Régularisation des charges — gate CLIENT** réservé au palier `paid` : calcul + PDF 100 % côté client, donc restriction produit et **pas** frontière de sécurité (rien à protéger côté serveur).
- **Précédence volontaire** : le gate **LÉGAL prime** — un bail au forfait affiche le message d'inapplicabilité, PAS un upsell Pro (il serait trompeur de vendre une fonction que la loi n'autorise pas sur ce bail). Gate appliqué **aussi** au deep-link `?action=regularize`, qui contournait la section (un compte free atteignait le dialog par URL).
- Fail-closed pendant le chargement du tier → pas de flash du bouton. Clé l10n `chargeRegularizationProOnly` (FR + EN). Suites : functions 209 · Flutter 2505.

### PR #119 : TODO paiement — matrice free/Pro validée + essai 7 jours — DOC (2026-07-20)
- **Décision ferme** : quittance PDF + partage restent **GRATUITS** (cœur produit + instrument légal, loi 1989 art. 21). Gating Pro sur : régularisation des charges, quota documents, envoi auto email (FEAT-031), annonces (FEAT-051), simulateur avancé.
- Précision importante : **aucun envoi d'email serveur n'existe** (quittance = PDF client + Web Share natif / mailto). Le vrai levier de gating « email » est FEAT-031, à construire.
- Essai gratuit **7 jours** tranché. Le webhook le gère déjà (`INITIAL_PURCHASE` period_type TRIAL → `paid` ; fin → `EXPIRATION` → `free`) ; reste à câbler `trial_period_days` côté prix Stripe.

### Licence propriétaire + attribution éditeur Daki Studio — CHORE (2026-07-20, hors PR)
- Le dépôt était **public sans fichier LICENSE**. Ajout d'une licence propriétaire bilingue FR/EN (tous droits réservés, droit français) précisant que la consultation publique sur GitHub ne vaut ni licence libre ni autorisation tacite de réutilisation.
- `README` (section Licence), `web/index.html` (meta author/copyright + publisher JSON-LD → « Daki Studio »), `ios/Runner/Info.plist` (`NSHumanReadableCopyright`).
- Baillan reste le **nom du produit** ; Daki Studio est l'**éditeur**. `applicationId` et bundle identifier inchangés.

### PR #118 : Checklist vivante du paiement FEAT-044 — DOC (2026-07-20)
- Consolide en une checklist cochable tout le reste-à-faire du volet paiement : blocages/décisions, setup dashboards RevenueCat/Stripe/stores, config des secrets de déploiement, reste-à-construire client. État « déjà livré » (#108–#117) inclus.

### PR #117 : Stripe Checkout Session pour Baillan Pro web (approche A) — FEAT (2026-07-20)
- `createCheckoutSession` (onCall) crée une Stripe Checkout Session d'abonnement et renvoie l'URL hostée. Volet **web** de la monétisation (ADR 0002 §Amendement).
- Architecture « RevenueCat = plan de gestion » : web → Stripe Checkout → Stripe → RevenueCat (ingestion compte connecté) → `revenueCatWebhook` (#114) → `subscriptionTier`.
- **Le lien vers le compte passe par la metadata** : App User ID RevenueCat (= UID Firebase) posé sur la Checkout Session **ET** sur `subscription_data` (`RC_APP_USER_ID_METADATA_KEY = "rc_app_user_id"`, à faire correspondre au dashboard RevenueCat) ; `client_reference_id` en ceinture-bretelles.
- **La fonction n'accorde aucun droit** — le déverrouillage reste 100 % serveur via le webhook. Logique critique isolée en fonction pure `buildCheckoutSessionParams` → 5 tests.
- Dépendance `stripe` (^22.3.2). Suite functions : 202 tests. Config déploiement : `STRIPE_SECRET_KEY` (secret), `STRIPE_PRICE_PRO_MONTHLY`, `STRIPE_PRICE_PRO_ANNUAL`, `WEB_APP_BASE_URL`.
- ⚠️ Les redirections pointent vers `/pro/success` et `/pro/cancel`, **routes non déclarées dans le GoRouter à ce jour**.

### PR #116 : ADR 0002 amendé — checkout web = Stripe Checkout propre — DOC (2026-07-20)
- RevenueCat devient un **plan de gestion** (source de vérité unique des entitlements) et non le portail de paiement. Le checkout appartient à chaque plateforme : web → Stripe Checkout · Android → Play Billing · iOS → StoreKit, tous → RevenueCat.
- Lève le rejet initial « Stripe direct = deux webhooks » : RevenueCat reste le point d'ingestion unique. Le `revenueCatWebhook` livré en #114 gère le web **sans modification** (`storeOf` mappe déjà STRIPE/RC_BILLING → `web`).

### PR #115 : Suite Cloud Functions validée en CI — CI (2026-07-20)
- Les Cloud Functions sont un projet npm indépendant sous `functions/` ; leur suite vitest (197 tests à l'époque) **n'était validée qu'en local, aucun job CI ne la lançait**. Ajout d'un job `functions` (Node 20, `npm ci`) : lint + build (tsc déployable) + test, en parallèle du job Flutter.

### PR #114 : Webhook RevenueCat + réconciliation d'entitlements — FEAT (2026-07-20)
- Volet paiement de FEAT-044 (ADR 0002) : le back-end de déverrouillage Pro. **Aucune intégration client ici** (différée).
- `revenueCatWebhook` (**1re fonction `onRequest` du codebase**) : vérifie le header `Authorization` en **temps constant** contre `REVENUECAT_WEBHOOK_AUTH`, puis écrit `landlords/{uid}.subscriptionTier` (+ champs `pro*` de cache) via l'Admin SDK. **Règles Firestore inchangées** (tier client-immuable).
- **Idempotent + garde d'ordre** (`proLastEventAtMs`) : un event antérieur au dernier appliqué est ignoré — évite qu'un RENEWAL retardé écrase une EXPIRATION plus récente. Toujours 2xx après traitement ; 500 seulement sur panne inattendue (déclenche le retry).
- Mapping type→accès : `INITIAL_PURCHASE`/`RENEWAL`/`UNCANCELLATION`/`PRODUCT_CHANGE`/`SUBSCRIPTION_EXTENDED` → paid ; `NON_RENEWING_PURCHASE` → paid non renouvelable ; `CANCELLATION`/`BILLING_ISSUE` → paid tant que non expiré (grâce) ; `EXPIRATION`/`SUBSCRIPTION_PAUSED` → free ; `TRANSFER`/inconnu/`TEST` → no-op.
- `reconcileEntitlements` (onSchedule quotidien, `30 3 * * *` Europe/Paris) : filet de sécurité des webhooks manqués. Requête `proEntitlementActive == true` (ensemble borné) + filtre d'échéance **en mémoire** → **aucun index composite**. Fetcher injectable → coeur testable sans réseau. Ne fait jamais d'upgrade.
- Logique métier en fonctions pures exportées → 24 tests. Suite functions : 197.
- Déploiement : `firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH` et `REVENUECAT_API_KEY` **AVANT** `firebase deploy --only functions`.

### PR #113 : ADR 0002 — monétisation Baillan Pro via RevenueCat — DOC (2026-07-18)
- Acte l'architecture de paiement de FEAT-044 : RevenueCat comme couche unique sur les deux surfaces (IAP natif mobile + web), une entitlement `pro`, mensuel + annuel. Statut : proposé → **accepté** (2026-07-18).
- Déverrouillage **serveur autoritaire** via webhook `onRequest` écrivant `subscriptionTier` (règles Firestore inchangées) ; réconciliation `onSchedule` **obligatoire** (les webhooks sont manquables).
- **TVA UE** : Baillan devient merchant of record sur le web (Stripe Tax), contrairement au mobile où le magasin l'est.
- Alternatives rejetées : Stripe-direct + IAP ; Apple/Google Pay sur mobile (interdit) ; achat web-only. Cadre de frais / politique magasins UE (DMA) vérifié mi-2026, à re-vérifier au build.

### PR #112 : e2e registre locatif utilisateur FREE + 1re couverture `createPayment` — TEST (2026-07-17)
- Enchaîne les **vraies** Cloud Functions (createProperty → createTenant → createLease → createPayment) comme un seul landlord FREE bâtissant un registre cohérent, IDs réels threadés d'une étape à l'autre.
- Comble deux trous : aucun test ne chaînait les 4 callables bout-en-bout (les existants les testent isolément, **en tier `paid`** pour neutraliser le gate FEAT-044) ; et **`createPayment` n'avait AUCUNE couverture** — ce fichier est sa première.
- Couvre la cohérence cross-entité + l'incrément des compteurs de plan + les plafonds FREE opposés en cours de registre (3e bien refusé, 4e locataire refusé → `resource-exhausted`). Suite functions : 173.

### PR #111 : e2e registre locatif — bien→locataire→bail→paiement, done/late — TEST (2026-07-17)
- Comble le trou signalé : aucun test ne chaînait le flux complet du registre locatif (les briques étaient couvertes isolément).
- `test/integration/rental_flow_lateness_test.dart` : construit les 4 entités avec IDs liés, round-trippe la sérialisation JSON de chacune (`fromJson(toJson())` = contrat de persistance CF), et prouve le basculement du **même** bail : paiement couvrant → à jour ; aucun paiement (échéance + grâce 5 j dépassées) → en retard ; paiement d'un autre mois → en retard ; bail résilié → jamais en retard (règle FEAT-028).
- Horloge figée pour n'avoir qu'un seul mois dû → basculement isolé. 5 tests.

### PR #110 : Défaut émulateur `127.0.0.1` au lieu de `localhost` — FIX (2026-07-17)
- Sur le web, Chromium résout `localhost` en IPv6 `::1`, mais les émulateurs firebase-tools n'écoutent que sur l'IPv4 `127.0.0.1`. **Résultat : l'app tombait silencieusement sur le backend PROD** (login en `invalid-credential`) au lieu de l'émulateur, sans erreur visible. Constaté en pilotant l'app web contre l'émulateur (#109).
- `127.0.0.1` force l'IPv4 et marche sur web/desktop/simulateur iOS. L'override Android (`10.0.2.2`) reste documenté.

### PR #109 : Toggle émulateurs Firebase (debug only) + ruban EMULATOR — FEAT (2026-07-17)
- Branche l'app Flutter sur les émulateurs (Firestore + Auth) pour le dev et les tests UI bout-en-bout, sans toucher la prod. Se combine avec `tool/seed/seed_tiers.mjs`.
- Activation : `--dart-define-from-file=dart-defines.emulator.example.json` (ou `USE_FIREBASE_EMULATOR=true`) ; hôte via `FIREBASE_EMULATOR_HOST`.
- **Garde-fou release (critique)** : `Env.useFirebaseEmulator = kDebugMode && flag`. `kDebugMode` étant une const `false` en release/profile, tout le bloc émulateur **et** le ruban sont éliminés par tree-shaking d'un build de prod — impossible qu'un build release pointe de vrais users vers un backend local, **même si le dart-define fuit dans la commande de build**.
- Ruban orange « EMULATOR » (`BannerLocation.topStart`) affiché uniquement quand le toggle est actif, pour ne jamais confondre données locales et prod.

### PR #108 : Seed de tiers émulateur + test du contrat SubscriptionTier — CHORE (2026-07-17)
- `tool/seed/seed_tiers.mjs` sème des landlords `free` et `paid` sur les émulateurs via l'Admin SDK. **Le palier `paid` n'a aucun chemin client** (règles : tier immuable côté client ; `finalize` n'écrit que `'free'` ; pas encore d'IAP) — l'Admin SDK, qui bypasse les règles, est le **seul** moyen de voir l'app en `paid` à cette date.
- **Garde-fou dur** : refuse de tourner sans `FIRESTORE_EMULATOR_HOST` (jamais la prod). Aucune dépendance ajoutée (`firebase-admin` résolu depuis `functions/node_modules`).
- `test/unit/subscription_tier_test.dart` fige le contrat SEED ↔ APP : round-trip des valeurs brutes, fail-safe (null/inconnu → `anonymous`), matrice de plafonds freemium sur l'enum.
- Non vérifié à l'époque : run émulateur bout-en-bout (pas de JRE sur la machine).

### PR #107 : Consigner #103 et #106 dans le changelog — DOC (2026-07-17)
- Les deux PR avaient été mergées sans embarquer leur entrée de changelog. Rattrapage au bon rang chronologique. Rappel de convention : les bug fixes vont au CHANGELOG **sans FEAT-ID**.

### PR #106 : Labels système agent absents + garde-fous CI silencieux — FIX (2026-07-17)
- Les 8 labels système documentés dans [`docs/TICKETING.md`](../TICKETING.md) (§ « Activer les labels système ») n'avaient jamais été créés dans le repo : seul `bug` existait (avec les labels GitHub par défaut). Créés hors PR via `gh label create` (un label n'est pas du code) : `feature-request`, `agent-skip`, `agent-processing`, `agent-needs-info`, `agent-failed`, `agent-done`.
- Trois bugs, tous masqués par des `2>/dev/null || true` :
  - **ticket-agent** — `--add-label agent-processing` échouait (« 'agent-processing' not found », exit 1) et le `|| true` renvoyait 0 : le step se croyait OK, label non posé. Or c'est le **seul** garde-fou contre le re-pick (le filtre de `find-mature-ticket` l'exclut) → l'issue restait éligible et le cron l'aurait reprise chaque heure, relançant l'agent en boucle.
  - `agent-eligible` = **label fantôme** : référencé à un seul endroit du repo, absent de `TICKETING.md`, jamais créé → en échec systématique. C'est lui qui justifiait le `|| true`, qui emportait au passage l'échec de `--add-label`. Supprimé (même classe que l'alias `softDeleteDocument`, `8116432`).
  - **ticket-done.yml** — même panne que #101 : pas de checkout, pas de `GH_REPO` → `gh` sortait en « failed to run git: not a git repository », masqué en permanence par `|| true`. **Aucun `agent-done` n'avait jamais été posé depuis la création du workflow.** `GH_REPO` ajouté au job.
- Plus aucun `|| true` sur les ops de label : retirer un label simplement absent de l'issue ne fait pas échouer `gh` (exit 0) — seul un label inexistant dans le repo le fait, càd le fantôme supprimé ici.
- Vérifié contre l'API GitHub réelle, hors dépôt git (condition CI), sur une issue de test refermée : avant, la ligne complète sortait en 0 alors que le label n'était pas posé ; après, `agent-processing` / `agent-done` sont bien posés.

### PR #105 : Release — refus de taguer sans commit depuis le dernier tag — FIX (2026-07-17)
- **Bug** : pipeline de release **non idempotent**. `version.sh next auto` bumpait (patch) même avec **0 commit** dans le range depuis le dernier tag → un « Re-run all jobs » du deploy prod sur un SHA déjà publié créait un tag **neuf** + une GitHub Release au **changelog vide** (v1.0.0 → v1.0.1 → v1.0.2…). Le garde-fou `rev-parse --verify refs/tags/$TAG` (« existe déjà ») de `release.sh` ne pouvait **jamais** se déclencher dans le flux `auto` : le tag calculé était toujours neuf.
- **Correctif en deux points** : `release.sh` refuse de couper une release si le range est vide — signature greppable **« rien à publier »**, au point de mutation, à côté de son frère « existe déjà ». `version.sh` expose `pending` (nb de commits depuis le dernier tag) et ses `next`/`codename-next` ne bumpent plus sur range vide : ils rendent la version **déjà publiée**.
- **Contrainte structurante** (raison du découpage) : `version.sh next auto` est aussi appelé par le step « Determine version » de `deploy.yml` pour le **label du build prod**, *avant* le deploy. L'y faire échouer aurait cassé **tout le re-run** au lieu de le rendre bénin → le refus vit dans `release.sh`. Le re-build porte ainsi le bon label (`1.0.0`, et non une `1.0.1` fantôme) → re-run idempotent **de bout en bout**.
- `deploy.yml` : le step « Tag release » tolère « rien à publier » (`::warning`, run vert) comme re-run bénin, et continue de propager tout le reste avec son exit code (politique de PR #102, préservée).
- **Portée** : prod uniquement (`app_env == 'prod'`) → aucun effet sur staging. Ce chemin n'a **jamais tourné en CI** (`deploy.yml` versionné vit sur `develop`, qui ne déploie que staging) : première exécution au prochain `develop` → `main`.
- Vérifié en pilotant les vrais scripts dans un clone jetable **sans remote** : range vide → refus, aucun tag ; range non vide → tag toujours créé avec le bon bump (`feat` → minor, `fix`/`docs` → patch, `!` → major). Le dépôt a toujours **zéro tag** (correct : le versioning n'est pas encore publié sur `main`).
- Suite de **PR #102** (propagation des erreurs du step tag), dont le commentaire documentait ce bug comme « à traiter séparément » — commentaire mis à jour.
- Doc : `docs/VERSIONING.md` — « aucun commit depuis le dernier tag = aucune release ».

### PR #103 : ticket-agent — filtre jq rejetait les issues à labels annexes — FIX (2026-07-17)
- Le `select(.labels | inside([…]) | not | not)` de « Auto-pick oldest eligible » ressemblait à du code mort (double négation) mais n'en était pas : `not | not` est bien l'identité sur un booléen, seulement `inside()` renvoie `false` dès qu'un label sort de la liste autorisée. Le select ne gardait donc que les issues dont **tous** les labels ∈ {bug, feature-request, agent-*} — rejetant en silence toute issue portant un label annexe (`priority-high`, `P1`, `ui`…), càd la plupart des vraies issues, en contradiction avec l'intention documentée trois lignes plus haut.
- Bug latent jamais observé : le cron n'a commencé à tourner qu'avec le fix `GH_REPO` (#101, même jour). En prime, `inside()` compare en **sous-chaîne** et non en égalité (un label `ug`, `agent` ou `e` passait le filtre).
- Correctif : ligne supprimée (les 4 `select` suivants implémentent déjà l'intention documentée : bug OU feature-request, pas de label agent-*, > 3h). Détection `KIND` passée de `grep -q "bug"` sur les labels joints à `index("bug")` — une `feature-request` étiquetée `debug-tools` partait sinon à tort en `/fix-bug` une fois le filtre corrigé.
- Vérifié contre l'API GitHub réelle (issue #104 de test, `bug`+`priority-high`) : l'ancien filtre la rejette (`AUCUN`), le nouveau la sélectionne (`104`) ; la barrière des 3h reste inchangée.

### FEAT-052 : Feature Readiness Score — outillage dev (2026-07-17)
- Ajout de `tool/feature_ready.dart` : script Dart pur (aucune dépendance hors `dart:io`/`dart:convert`) qui note une feature sur 100 en 7 catégories pondérées et rend un rapport markdown sur stdout.
- **Lecture seule et non bloquant** : n'écrit aucun fichier du dépôt, sort toujours en 0 (sauf `--strict`, opt-in manuel). `.github/workflows/ci.yml` **n'est pas modifié**.
- **Déterministe** : aucun timestamp dans le rapport, collections triées ; deux exécutions sur le même arbre donnent un résultat identique à l'octet près (couvert par `test/unit/feature_ready_test.dart`).
- Commande `/feature-ready` (`.claude/commands/feature-ready.md`) : wrapper mince qui déduit le FEAT-ID de la branche et affiche le rapport sans le recalculer.
- La parité ARB réutilise la règle de `test/l10n/arb_parity_test.dart` (exclusion des clés `@…`) plutôt que de la redéfinir.
- **Renumérotation `FEAT-045` → `FEAT-052`** (deux collisions successives) : le plan initial portait `FEAT-045`, déjà attribué à « Suppression compte in-app » (✅ done, PR #69) et référencé sous ce sens par FEAT-046/047 dans `docs/BACKLOG.md`. Le premier report vers `FEAT-051` était lui aussi pris — « Baillan Pro — annonces & diffusion multi-portails » (discovery cadrée 2026-07-16, PR #98), invisible depuis `main` car mergée sur `develop` seulement. D'où `FEAT-052`. **Leçon** : vérifier les IDs libres depuis `develop`, jamais depuis `main` (qui retarde).
- Limite assumée : les catégories « Accessibilité » et « Complétude produit » sont un accusé de réception documentaire (le script lit le plan), pas une preuve de qualité — le rapport l'affiche.

## Changements (2026-07-03 → 2026-07-10)

### PR #94 : Verrouillage de la réactivation de bail (updateLease) — FIX (2026-07-10)
- Transition `terminated|archived → active` (réactivation) imposait seulement une vérification d'existence du bien/locataire, pas soft-delete.
- Résolution : Appel failed-precondition si le bien ou le locataire est soft-deleted lors de la réactivation — prévient la résurrection de baux vers des entités supprimées.
- Recompte atomique fail-closed du plafond `landlors.activeLeasesCount` en cas de compteur absent (legacy).
- Impact : shards leases.md + functions/leases.md actualisés.

### FEAT-044 + Corrections shards — QA pré-release 2026-07-10
- Shards payments-receipts.md, schema/account.md, schema/properties.md, functions/properties.md, functions/leases.md actualisés post-PR #91 (freemium) + PR #94 (réactivation):
  - **payments-receipts.md** : Champ `paidAt` corrigé (non `paidDate`). Receipts schema refactorisé : champs réels (paymentIds, rentCents, chargesCents, totalCents, documentType, isVoided, isStale, sentAt) ; pas de receiptNumber séquentiel, pas d'amountCents unique, pas de Storage PDF (généré client), pas de trigger auto-génération. Indexes/RLS/Callables/Triggers actualisés.
  - **account.md** : Ajout champs `phone`, `address`, `fullName` sur landlords. Compteurs FEAT-044 documentés : `activePropertiesCount`, `activeTenantsCount`, `activeLeasesCount`. rgpdConsentVersion mise à jour : v2-2026-07 → v3-2026-07.
  - **properties.md** : Create = if false (CF-exclusive). Champs property FEAT-017 (financing) : ~25 champs documentés (loan*, tax*, insurance*, DPE, surface, rooms, etc.). Callables `createProperty`/`createTenant` avec gating free-tier (2 biens, 3 locataires) documentés.
  - **leases.md** : Compteurs FEAT-044 (activeLeasesCount sur landlords/properties/tenants). PR #94 (réactivation verrouillée) : bien/locataire doivent exister et non soft-deleted.
  - **functions/leases.md** : updateLease détail réactivation (PR #94) + plafonds (free=2, paid=∞).
  - **functions/properties.md** : createProperty/createTenant callables avec plafonds FEAT-044.
  - Champs tenant enrichis documentés (phone, birthDate, profession, guarantor, monthlyIncome, etc.).

## Changements (2026-07-03 → 2026-07-08)

### FEAT-049 : SEO du PWA (quick-wins, Option A) — ✅ DONE (PR #73, 2026-07-08)
- Contenu enrichi `web/index.html` : `<html lang="fr">`, title/description riches, Open Graph + Twitter Card, JSON-LD (Organization/SoftwareApplication/WebSite), bloc HTML statique crawlable en tête de `<body>`.
- Plomberie SEO : `web/robots.txt` (prod), `web/robots.staging.txt` (Disallow *), `web/sitemap.xml`, headers `firebase.json` (Cache-Control robots/sitemap).
- Noindex staging : étape `deploy.yml` (gated APP_ENV=dev) swap robots + meta noindex.
- Pipeline Growth : agent `seo-specialist` + workflow `seo-audit.js`. Doc `docs/SEO.md`.
- Fait structurant : Flutter CanvasKit peint canvas (non indexable) → Option B (site marketing statique) = seul vrai levier non-brand.

### FEAT-050 : Site marketing statique crawlable (Option B) — 📋 PLANNED
- Topologie confirmée : `baillan.fr` (site statique Astro/Hugo, contenu crawlable) + `app.baillan.fr` (app Flutter, noindex, canonique).
- Dépendances : FEAT-049 complet, domaine custom. Spec : `docs/backlog/050-marketing-site-seo.md`. Timing post-lancement MVP.

### FEAT-043 : i18n FR/EN — ✅ DONE (PR #71, 2026-07-08)
- Fondation gen_l10n : ARB `app_{en,fr}.arb` (~800+ clés), localeProvider (SharedPreferences), locale système défaut.
- Erreurs localisées : ValidationError + AuthError → extensions `.message(context)`. Pattern freezed : states stockent `error.name` (string) → présentation via l10n.
- Coverage : toutes features bilingues. Note : e-mails et formatters dates/€ restent FR (post-M1) ; le flux de suppression de compte est désormais bilingue FR/EN (FEAT-045 i18n, PR #72) — le contenu légal (« 5 ans », loi 89-462) reste FR par design.

### FEAT-048 : FAQ produit publique + réordonnancement hub Profil — ✅ DONE (PR #69, 2026-07-07)
- Route `/faq` (publique). 11 Q/R (quittances loi 1989, essai anonyme, RGPD, suppression, charges…). ExpansionTiles.
- Hub Profil réordonné : Compte / Apparence / Aide (FAQ, contact, légal) / À propos / Session.

### FEAT-045 : Suppression de compte in-app + page publique /delete-account — ✅ DONE (PR #69, 2026-07-07)
- Bloquant stores levé (Google Play 13327111 + App Store 5.1.1(v)).
- CF callable `deleteAccount` : garde fraîcheur token (auth_time < 5 min, anonymes exemptés), quittances CONSERVÉES 5 ans (loi 6/07/1989, stamp accountDeletedAt + retentionUntil), hard-delete paginé 8 collections + singletons + Storage, Auth supprimé EN DERNIER.
- AuthRepository : `reauthenticateWithOAuthProvider`, `revokeAppleToken` (best-effort), `deleteAccount`.
- UI : tuile hub /profile → `/profile/delete-account` ; page publique `/delete-account`. Privacy policy v1.2. Tests : 11 vitest CF + 22 Flutter.

### FEAT-024 : App mobile iOS/Android — ✅ DONE (2026-07-06)
- Plateformes natives `android/` + `ios/`, bundle ID `com.daki.baillan`. Firebase apps Android+iOS sur `easy-rent-54cd4`, `firebase_options.dart` couvre web/android/ios.
- Auth OAuth Google/Apple via `signInWithProvider` mobile (popup web). Partage quittances share sheet natif `share_plus`.
- Validé : analyze clean, 2386 tests, APK debug, parcours anonyme émulateur, build iOS simulateur.
- Conformité stores (2026-07-07) : audit `STORE_COMPLIANCE.md`. Bloquants : suppression compte (FEAT-045 ✅), formulaires consoles, DSA trader, mentions LCEN.
- Reste : signing release, capability Apple Sign-In, icônes/splash natifs, QA devices.

### FEAT-042 : Mode de charges (provisions/forfait) — ✅ DONE (PR #68, 2026-07-06)
- `leases.chargeMode` (string?, 'provisions'|'forfait'). Migration lazy (null dérivé du leaseType).
- CF helper `resolveChargeMode(leaseType, requested)` (source vérité serveur). Forfait ⇒ nonRecoverableChargesCents = 0.
- Éligibilité régularisation : prédicat `canRegularizeCharges` (effectiveChargeMode==provisions). Horloge injectable `listForDisplay({now})`.

### FEAT-041 : Suivi dépenses unifié (V1) — ✅ DONE (PR #67, 2026-07-05)
- Collection `expenses/{id}` (CF exclusive). `NATURE_DEFAULT_CATEGORY` (décret 87-713) : category dérivée serveur depuis nature.
- Nature enum (condo_charges|property_tax|insurance_pno|management_fees|works|repair_maintenance|other). Category (recoverable|non_recoverable).
- Routes `/properties/:id/expenses*`. FEAT-041b : documents v2 (category 'expense_receipt'). FEAT-041c (planné V1.1) : recomputeChargeRegularization trigger. 3 index composites. 2 callables + 1 trigger.

### FEAT-036 : Charges récupérables vs non-récupérables — ✅ DONE (PR #66, 2026-07-05)
- `leases.nonRecoverableChargesCents` (int ≥ 0). `chargesAmountCents` = récupérable (bilancée) ; nonRecoverable = informatif bailleur (décret 87-713).
- UI dual inputs. CF createLease/updateLease (default 0). `validateNonRecoverableCharges()`.

### FEAT-030 : Navigation retour corrigée — ✅ DONE (7db144d)
- Formulaires → pop() ; tuiles Accueil → push() ; bouton Profil retiré de la fiche bail ; simulateur → push().

### FEAT-029b : Découvrabilité régularisation — ✅ DONE (514666f)
- Menu « Régulariser les charges » sur carte/ligne bail nu ; `/leases/:id?action=regularize` auto-ouvre dialog.

### FEAT-029 V1 : Charges — motif + régularisation — ✅ DONE (871ebff)
- Motif libre sur reçu (payment.notes → PDF). Régularisation annuelle (bail nu) : `lib/features/charge_regularization/**`. Calcul provisions client + avis PDF partagé. Pas d'archivage (V2).

### FEAT-028 : Détection retards corrigée — ✅ DONE (7ac1d03)
- `lease_lateness.dart` : isLeaseLate() testable (grâce 5j, pas prorata 1ᵉʳ mois). LeaseFilter.late + KPI drill-down. Pastille « En retard ». Priorité : retard > renewable > active.

### FEAT-027 : Dashboard — période graphique sélectionnable — ✅ DONE (ba7c12d)
- chartPeriodProvider (6/12/24 mois) persisté. monthlyAmountsProvider découplé.

### FEAT-026 : Navigation shell adaptative — ✅ DONE (ca2d10a)
- StatefulShellRoute.indexedStack 5 branches (Accueil/Biens/Locataires/Baux/Profil). NavigationBar <600px / NavigationRail ≥600px repliable (railExpandedProvider persisté). Marque Baillan en tête. Simulateur + landing + auth + légal hors shell.

### FEAT-025b : /profile HUB de réglages — ✅ DONE (16ebc77)
- ProfilePage tuiles + sous-pages `/profile/{details,password,support}`.

### FEAT-025 : Sécurité + support — ✅ DONE (0cd54de, f5734b4)
- Changement mot de passe in-app (reauthenticateWithPassword + updatePassword, gate hasPasswordProvider).
- Support : collection `support_requests` (create-only, rules strictes). Privacy policy v1.1.

### FEAT-023 : Réglages app — ✅ DONE
- Thème Système/Clair/Sombre persisté (themeModeProvider). Liens légaux /terms + /privacy. Section À propos (package_info_plus).

### CGU v2-2026-07 — ✅ DONE
- Page `/terms`. Acceptation CGU + confidentialité au signup. rgpdConsentVersion : `v1-2026-06` → `v2-2026-07`.

### Functions : handleNewUser supprimé — ✅ DONE (90eb86f)
- ADR 0001 : GCIP non activé (assumé). handleNewUser (beforeUserCreated) supprimé → deploy functions débloqué. Provisioning landlord 100 % client. build = tsc -p tsconfig.build.json.

### FEAT-018 : Simulateur investissement — ✅ DONE
- `/simulator` (list/create) + `/simulator/:id` (edit). Accessible anonymes + comptes (investment_scenarios CRUD direct).

## Audit incohérences (2026-07-06, commit 6367a8c)

- ✅ **11 collections** Firestore cohérentes (landlords, properties, tenants, leases, payments, receipts, documents, expenses, investment_scenarios, paid_plan_interest, support_requests) — camelCase stable.
- ✅ Règles 3 couches (rules + CF + triggers), isFullyAuthed()/isAnonymous(), soft-delete systématique, expenses CF exclusive.
- ✅ 28+ index composites (soft-delete + cross-filters, incl. expenses 3 index).
- ✅ Cloud Functions : 27→28 callables + 8 triggers + 1 scheduled.
- ✅ 45+ routes GoRouter, 3-état guard via sessionStateProvider.
- ✅ FEAT-036/041/042 intégrés (dual charges, expenses collection + dérivation juridique, chargeMode + resolveChargeMode + canRegularizeCharges + forfait forcing).
- ✅ Persistence : themeModeProvider + chartPeriodProvider + railExpandedProvider (SharedPreferences).
- ✅ Anonyme tier BAILLAN-M1 (14j essai, upgrade transactionnel).
