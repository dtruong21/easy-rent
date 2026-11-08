# Audit de sécurité OWASP — Baillan (EasyRent) — 2026-09-30

## Statut des correctifs (2026-09-30)

> Ajouté après les correctifs de la branche `fix/owasp-security` (plan [`docs/superpowers/plans/2026-09-30-owasp-security-fixes.md`](../superpowers/plans/2026-09-30-owasp-security-fixes.md)). Le reste du rapport est **inchangé** : il décrit l'état au HEAD `a4df800` audité, pas l'état corrigé.
> **Rien n'est déployé** par ces commits : **redéploiement manuel des Functions requis** ; règles Firestore par la CI (`firestore:staging` sur `develop`, `(default)` sur `main`) ; `storage.rules` par `deploy.yml` depuis `main` seulement (bucket partagé) ; en-têtes Hosting par la CI avec le Hosting. Détail et action manuelle RevenueCat : [`docs/SECURITY.md`](../SECURITY.md).

| ID | Sév. | Statut | Détail / où |
|---|---|---|---|
| OWASP-01 | Élevée | **Corrigé** — `c88f361` | Webhook routé par `event.environment` (`SANDBOX` → `staging` seul, `PRODUCTION` → `(default)` seul, autre → ignoré, aucun repli) ; `createCheckoutSession` refuse `landlord_not_found` ; cron `reconcileEntitlements` ignore les entitlements `is_sandbox`. **Résidus** : (a) webhook RevenueCat « Production only » non appliqué — action manuelle, et il couperait aussi les events `SANDBOX` qui alimentent `staging` ; (b) une `Origin` localhost forgée ouvre encore une session Stripe test contre un compte prod (aucun palier accordé : le webhook route `SANDBOX` → `staging`) ; (c) les achats sandbox d'App Review / TestFlight sur un compte prod ne débloquent plus rien → allowlist serveur à prévoir avec la feature achat intégré ; (d) valeurs réelles d'`environment` à confirmer après déploiement ; (e) relevé en relecture, non reproduit : le cron pourrait rétrograder un compte prod payant qui détient aussi un achat sandbox à échéance plus lointaine. |
| OWASP-02 | Moyenne | **Corrigé** — `7c8ef23` | `hasTrustedEmail()` exigée par `isFullyAuthed()` / `isOwner()` (exception : création de son propre `landlords/{uid}` à l'inscription) ; `requireVerifiedUid` sur 22 callables (exemptées : `deleteAccount`, `exportAccountData`, `finalizeAnonymousUpgrade`) ; tests de règles et de parité. Suivi client (non fait) : forcer le rafraîchissement du jeton après la vérification (`getIdToken(true)`). |
| OWASP-03 | Moyenne | **Reporté** | Hors périmètre du plan : chantier App Check séparé (`firebase_app_check`, `enforceAppCheck`, quotas par uid). Aucun changement de code. |
| OWASP-04 | Moyenne | **Corrigé (partiel)** — `3221965` | Écriture Storage réservée aux comptes non anonymes à email de confiance, nom d'objet `{id 20 car.}.(pdf\|jpg\|png\|webp)`, `cleanupExpiredAnon` purge `documents/{uid}/`. **Reporté** : purge des objets orphelins non référencés (job ou lifecycle du bucket) — à ouvrir en issue. |
| OWASP-05 | Moyenne | **Corrigé** — `9922767` | `deleteAccount` hard-delete aussi `charge_statements` et `etat_des_lieux` ; test de parité export ⊆ purgé ∪ retenu (`receipts`) ; `docs/LEGAL.md` mis à jour. **Reste** : les comptes supprimés avant le correctif ont pu laisser ces documents (script ponctuel non écrit) ; l'avertissement du flux de suppression ne cite pas ces PDF (suivi UX). |
| OWASP-06 | Moyenne | **Corrigé (partiel)** — `c0e5f19` | `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, `X-Frame-Options: DENY` sur les 4 cibles ; vitrine : CSP appliquée ; app : `frame-ancestors 'none'` appliqué + CSP complète en **Report-Only** (7 hashes liés à `web/index.html` et FlutterFire). **Reste** : promouvoir la CSP de l'app en politique appliquée après observation sur staging (PDF de quittance via `window.open(blob:)`, popup d'auth) ; pas de `report-uri`. HSTS : indiqué comme ajouté par défaut par Firebase Hosting dans le commentaire de `firebase.json`, non revérifié ici. |
| OWASP-07 | Moyenne | **Reporté** | Chantier structurel (projet Firebase distinct pour le staging, ou allowlist `stagingTester`). OWASP-01 supprime la conséquence la plus grave (palier accordé en prod) mais pas le reste (`deleteAccount` depuis staging, crons sur `(default)` seul…). |
| OWASP-08 | Moyenne | **Reporté** | Hors périmètre (workflow CI `ticket-agent.yml`) ; confirmer d'abord la visibilité du dépôt et la protection des branches. |
| OWASP-09 | Moyenne | **Corrigé (partiel)** — `b6d5e7c` | `npm audit fix` sur `functions/` (lockfile seul) : advisories de prod 16 (5 high) → 9 (2 high), chiffres mesurés par la tâche (l'audit en comptait 13, 1 high). **Reste** : firebase-admin 14 / firebase-functions 7 (montées majeures) à planifier ; Dependabot absent (pas de `.github/dependabot.yml`). |
| OWASP-10 | Faible | **Reporté** | Non traité dans ce lot (gel des champs `pro*` à la création du landlord). |
| OWASP-11 | Faible | **Reporté** | Non traité dans ce lot (rollback de `createDocument`). |
| OWASP-12 | Faible | **Reporté** | Non traité dans ce lot (password policy Identity Platform, réglage console). |
| OWASP-13 | Faible | **Reporté** | Non traité dans ce lot (bornes de taille des entrées). |
| OWASP-14 | Faible | **Reporté** | Non traité dans ce lot (sauvegarde Android, signature release). |
| OWASP-15 | Faible | **Reporté** | Non traité dans ce lot (journalisation et alerting). |
| OWASP-16 | Faible | **Reporté** | Non traité dans ce lot (actions CI épinglées par SHA). |
| OWASP-17 | Info | **Reporté** | Non traité dans ce lot (obfuscation mobile). |
| OWASP-18 | Info | **Reporté** | Non traité dans ce lot (expiration d'inactivité de la session web). |
| OWASP-19 | Info | **Reporté** | Non traité dans ce lot (filtrage des messages Crashlytics). |
| OWASP-20 | Info | **Reporté** | Non traité dans ce lot (montée FlutterFire, à confirmer). |
| OWASP-21 | Info | **Corrigé** — `3221965` | Suite `functions/rules-tests/storage_rules.test.ts` (34 cas) ajoutée avec OWASP-04, exécutée par `npm run test:rules` (émulateurs Firestore + Storage ; clé de cache CI `v2`). |

Ce lot n'a créé aucun ticket pour les constats « Reporté » ni pour les résidus listés ci-dessus : à ouvrir avant le prochain lot sécurité.

---

- **Périmètre** : dépôt `easy-rent`, branche `develop`, HEAD `a4df800` (merge PR #206).
  App Flutter (web PWA, iOS, Android), Cloud Functions TS (`functions/src/`),
  `firestore.rules`, `storage.rules`, `firebase.json`, workflows CI
  (`.github/workflows/`), vitrine Astro (`site/`).
- **Méthode** : revue de code manuelle ligne à ligne des règles et de chaque
  callable / webhook / cron, scans grep (secrets dans l'arbre ET l'historique git,
  valeurs masquées), `npm audit --omit=dev` sur `functions/` et `site/`.
  Audit en **lecture seule** : aucun service déployé n'a été appelé (Firebase,
  Stripe, RevenueCat, GitHub API). Les constats qui dépendent d'une configuration
  de console sont marqués **« à confirmer »**.
- **Référentiels** : OWASP Top 10 2021 (A01–A10), OWASP API Security Top 10
  2023 (API1–API10), OWASP MASVS v2.

---

## 1. Résumé exécutif

**Verdict global : BLOQUANT pour l'ouverture des ventes Pro/Max/Ultra ;
correction de OWASP-01 recommandée immédiatement** (la faille est exploitable
dès aujourd'hui, le chemin serveur ne dépendant pas du drapeau client
`SUBSCRIPTIONS_ENABLED`).

Le cloisonnement des données entre bailleurs est **solide** : aucun accès
inter-comptes (BOLA/IDOR) n'a été trouvé, ni dans les règles Firestore/Storage ni
dans les 25 callables. Les règles sont deny-by-default, les `list` sont bornés au
propriétaire, toutes les écritures cross-entity passent par des callables qui
dérivent l'uid du seul jeton et re-vérifient la propriété de chaque identifiant
reçu. Aucun secret n'a été trouvé dans le code ni dans l'historique git.

Le risque principal est **d'intégrité métier** : l'environnement de staging est
public et partage l'Auth, les Functions et (vraisemblablement) le webhook
RevenueCat avec la prod ; un achat Stripe **en mode test** (carte de test
publique) depuis le staging accorde un palier payant **en production**.
Viennent ensuite des faiblesses de conception anti-abus (pas d'App Check, pas de
limitation de débit, email non vérifié côté serveur, Storage ouvert aux
anonymes) et un trou RGPD dans la suppression de compte.

| Sévérité | Nombre |
|---|---|
| Critique | 0 |
| Élevée | 1 |
| Moyenne | 8 |
| Faible | 7 |
| Info | 5 |
| **Total** | **21** |

Ordre de remédiation recommandé : OWASP-01 → OWASP-05 → OWASP-02 → OWASP-04 →
OWASP-03 → OWASP-08 (confirmer la visibilité du dépôt d'abord) → OWASP-07 →
OWASP-09 → OWASP-06 → constats Faibles.

---

## 2. Tableau des constats

### OWASP-01 — Palier payant accordé en production par un achat Stripe en mode test (staging)

| Champ | Contenu |
|---|---|
| Sévérité | **Élevée** (exploitabilité très forte × impact financier total ; aucune fuite de données) |
| Références | A04 Insecure Design, A01 Broken Access Control ; API6:2023 Unrestricted Access to Sensitive Business Flows, API10:2023 Unsafe Consumption of APIs |
| Fichiers | `functions/src/http/revenuecat_webhook.ts:64-73`, `:209-233`, `:345` ; `functions/src/utils/db_router.ts:98-106` ; `functions/src/callable/create_checkout_session.ts:226-242` ; `.github/workflows/deploy.yml:69-80` ; `functions/src/utils/stripe_env.ts:19-23` |
| Preuve | Le webhook ne lit jamais `event.environment` (`SANDBOX`/`PRODUCTION`) : l'interface `RcEvent` (l. 64-73) ne le déclare pas, aucun `environment`/`is_sandbox` dans `functions/src/`. La base cible est choisie par `dbForLandlordUid(event.app_user_id)` (l. 345), qui teste **la prod d'abord** (`db_router.ts:101-102`). Côté checkout, une origine `https://app.staging.baillan.com` (réelle ou forgée) obtient la clé `sk_test` (`resolveStripeKeyOrThrow`), et un doc landlord **absent** de la base routée laisse passer (`assertCanOpenCheckout(null)`, l. 228-232). Le staging est public avec `subscriptions_enabled=true` (`deploy.yml:73-75`). |
| Scénario | Un utilisateur prod (compte vérifié dans `(default)`) se connecte sur le staging (Auth partagée) ou forge l'en-tête `Origin` → Checkout Stripe test → paie avec la carte de test publique `4242…` → Stripe test → RevenueCat → webhook → `dbForLandlordUid` trouve le doc **prod** → `subscriptionTier: "paid"`, `planLevel` jusqu'à `ultra` en prod. Le commentaire `stripe_env.ts:19-23` (« aucun entitlement prod accordé ») est donc faux dans ce cas ; `db_router.ts:94-96` le reconnaît comme une « discipline » de test, pas comme une garde. Le cron `reconcileEntitlements` ne corrige pas si l'API REST RevenueCat rapporte aussi les abonnements sandbox (**à confirmer**) ; un abonnement Stripe test se renouvelle indéfiniment. |
| Impact | Contournement complet de la monétisation (quotas Max/Ultra gratuits pour tout compte), coûts d'infrastructure non compensés. |
| Recommandation | (1) Dans `applyRevenueCatEvent`, ajouter `environment` à `RcEvent` et **refuser tout event `SANDBOX` quand la base résolue est `(default)`** (et, symétriquement, n'accepter en `staging` que du `SANDBOX`) ; test unitaire dédié. (2) Côté RevenueCat, **à confirmer** : webhook prod configuré « Production only », webhook staging distinct. (3) Dans `createCheckoutSession`, en environnement `test`, refuser si `landlords/{uid}` existe dans `(default)` (compte prod) ou n'existe pas dans `staging`. (4) Dans le fetcher du cron, ignorer les entitlements issus d'achats sandbox. (5) Structurellement, voir OWASP-07. |

### OWASP-02 — Vérification d'email non appliquée côté serveur

| Champ | Contenu |
|---|---|
| Sévérité | **Moyenne** |
| Références | A07 Identification & Authentication Failures ; API2:2023 Broken Authentication ; MASVS-AUTH |
| Fichiers | `firestore.rules:40-42`, `:79-80` ; `functions/src/utils/callable_helpers.ts:24-29` ; `functions/src/callable/finalize_anonymous_upgrade.ts:156` ; `lib/features/auth/application/login_controller.dart:45-55` |
| Preuve | `isFullyAuthed()` = `isSignedIn() && !isAnonymous()`, sans `request.auth.token.email_verified` (le commentaire l. 36 parle pourtant de « email/password vérifié »). `requireAuthUid` ne contrôle que `request.auth`. `finalizeAnonymousUpgrade` n'exige qu'un provider lié (`providerData.length === 0`). Le seul contrôle est client : `login_controller.dart:45` déconnecte si `!emailVerified`. |
| Impact | Un compte email/mot de passe jamais vérifié — y compris créé avec l'adresse d'un tiers — utilise tout le produit via le SDK/REST (rules + callables) ; `createCheckoutSession` pose l'email non vérifié du jeton comme `customer_email` Stripe ; création de comptes en masse facilitée (cf. OWASP-03/04). |
| Recommandation | Ajouter à `isFullyAuthed()` : `(request.auth.token.email_verified == true \|\| request.auth.token.firebase.sign_in_provider in ['google.com','apple.com'])`, et un helper `requireVerifiedUid()` dans les callables métier (hors `deleteAccount`/`exportAccountData`, qui doivent rester accessibles). Tests rules cross-cas. |

### OWASP-03 — Aucune attestation d'app ni limitation de débit ; backend saturable

| Champ | Contenu |
|---|---|
| Sévérité | **Moyenne** |
| Références | A04 Insecure Design ; API4:2023 Unrestricted Resource Consumption ; MASVS-RESILIENCE |
| Fichiers | `functions/src/index.ts:47-51` ; `pubspec.yaml` (pas de `firebase_app_check`) ; aucun `enforceAppCheck` dans `functions/src/` ; `docs/SECURITY.md:25` ; `firebase.json` (`auth.providers.anonymous: true`) |
| Preuve | `setGlobalOptions({maxInstances: 2, cpu: "gcf_gen1"})` : ~0,17 vCPU × 2 instances par fonction. Toutes les écritures métier passent par des callables. La connexion anonyme fournit un jeton valide sans friction. Aucun quota par uid (ex. `exportAccountData`, `createCheckoutSession`, `createDocument`, `createScenario`). |
| Impact | Déni de service applicatif à faible coût (saturer `createPayment`/`generateReceipt` bloque tous les bailleurs) ; création illimitée de sessions Checkout avec la clé live (risque de rate-limit Stripe). Le plafond d'instances protège la facture, pas la disponibilité. |
| Recommandation | Activer App Check (reCAPTCHA Enterprise web, Play Integrity, App Attest) puis `enforceAppCheck: true` sur les callables et l'enforcement Firestore/Storage ; quotas par uid (compteur Firestore à fenêtre) sur les callables coûteuses ; relever `maxInstances` des callables d'écriture critiques ; quotas Identity Platform sur l'inscription anonyme. |

### OWASP-04 — Storage : téléversements illimités, ouverts aux anonymes, orphelins jamais purgés

| Champ | Contenu |
|---|---|
| Sévérité | **Moyenne** |
| Références | A04 Insecure Design ; API4:2023 ; A01 (contrôle d'accès trop large) |
| Fichiers | `storage.rules:50-55` ; `functions/src/scheduled/cleanup_expired_anon.ts:119-135` ; `functions/src/callable/documents.ts:299-304` |
| Preuve | `allow create: if request.auth != null && request.auth.uid == landlordId && size <= 50 Mio && contentType…` : aucun test anonyme/email vérifié, aucune contrainte de nom d'objet, aucun nombre maximal. Le quota « documents » (0 pour anonymous) n'est appliqué que dans `createDocument`, qu'un client peut ne jamais appeler. `cleanupExpiredAnon` ne purge pas `documents/{uid}/`. Pas de règle de cycle de vie dans le dépôt (commentaire l. 56-58 « plus tard »). |
| Impact | N'importe quel compte anonyme (création gratuite, illimitée) peut stocker un nombre illimité d'objets de 50 Mio dans le bucket partagé prod/staging : coût facturé indéfiniment, bucket pollué. |
| Recommandation | Règle : `request.auth.token.firebase.sign_in_provider != 'anonymous'` (+ email vérifié), nom contraint (`file.matches('[A-Za-z0-9]{20}\\.(pdf\|jpg\|jpeg\|png\|webp)')`) ; purge Storage dans `cleanupExpiredAnon` ; job/lifecycle qui supprime les objets `documents/**` non référencés après 24 h ; tests de règles Storage (inexistants aujourd'hui, cf. OWASP-21). |

### OWASP-05 — Effacement RGPD incomplet : décomptes de charges et états des lieux conservés sans limite

| Champ | Contenu |
|---|---|
| Sévérité | **Moyenne** |
| Références | A04 Insecure Design (privacy by design) ; MASVS-PRIVACY ; RGPD art. 17 et 5.1.e |
| Fichiers | `functions/src/callable/delete_account.ts:129-138` ; `functions/src/scheduled/purge_expired_receipts.ts:43-47` ; `docs/LEGAL.md:35-40` ; `functions/src/callable/etat_des_lieux.ts:117-134` |
| Preuve | `PURGED_COLLECTIONS` = properties, tenants, leases, payments, documents, expenses, investment_scenarios, support_requests. `charge_statements` (FEAT-033) et `etat_des_lieux` (FEAT-037) n'y sont pas, et ne reçoivent pas non plus `retentionUntil` (`stampRetainedReceipts` ne traite que `receipts`). Le cron de purge ne lit que `receipts`. `docs/LEGAL.md:35` promet pourtant « tout le reste est hard-delete immédiat ». |
| Impact | Après suppression de compte, les documents figés contenant `landlordFullName`, `landlordAddress`, `tenantFullName`, `propertyAddress`, relevés et commentaires restent en base **sans échéance** (inaccessibles via les règles, mais conservés) — non-conformité à la politique de confidentialité déclarée aux stores. |
| Recommandation | Soit les ajouter à `PURGED_COLLECTIONS`, soit les traiter comme les quittances (stamp `retentionUntil` + extension du cron) et mettre à jour LEGAL.md / politique de confidentialité. Ajouter un test de parité : `EXPORTED_COLLECTIONS` ⊆ `PURGED_COLLECTIONS ∪ {receipts, …retenues}`. Corriger les comptes déjà supprimés (script ponctuel). |

### OWASP-06 — En-têtes de sécurité HTTP absents (app et vitrine)

| Champ | Contenu |
|---|---|
| Sévérité | **Moyenne** |
| Références | A05 Security Misconfiguration ; API8:2023 Security Misconfiguration |
| Fichiers | `firebase.json:17-86` (cible `prod`), `:102-170` (`stage`), blocs `marketing` / `marketing-stage` |
| Preuve | Seuls `Cache-Control` et `X-Robots-Tag` sont définis. Aucun `Content-Security-Policy`, `frame-ancestors`/`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`. `web/index.html` contient des scripts inline, sans meta CSP. HSTS : probablement ajouté par défaut par Firebase Hosting — **à confirmer** sur les réponses réelles. |
| Impact | Aucune défense en profondeur si un script tiers ou injecté s'exécute (le jeton Firebase vit en IndexedDB, lisible par tout script de l'origine) ; app encadrable par un site tiers (clickjacking — atténué par la ré-authentification exigée pour la suppression). |
| Recommandation | Bloc `headers` `source: "**"` sur les 4 cibles : `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` restrictive, `Content-Security-Policy` avec `frame-ancestors 'none'` et `connect-src` limité aux endpoints Firebase/Stripe (démarrer en `Content-Security-Policy-Report-Only` : Flutter/CanvasKit exige `'wasm-unsafe-eval'` et `https://www.gstatic.com`, et les scripts inline d'`index.html` doivent passer par hash). |

### OWASP-07 — Isolation staging/prod partielle : staging public adossé à l'Auth, au Storage et aux Functions de prod

| Champ | Contenu |
|---|---|
| Sévérité | **Moyenne** |
| Références | A05 Security Misconfiguration, A04 ; API9:2023 Improper Inventory Management |
| Fichiers | `functions/src/utils/db_router.ts:56-58`, `:75-83` ; `functions/src/callable/delete_account.ts:160-199` ; `functions/src/scheduled/cleanup_expired_anon.ts:43-51` ; `functions/src/scheduled/purge_expired_receipts.ts:70-72` ; `.github/workflows/deploy.yml:69-80` ; `.firebaserc` |
| Preuve | Le staging (`develop`, code non relu pour la prod) est servi publiquement et partage projet, Auth, bucket et Functions (ADR 0003, « limitations assumées »). `deleteAccount` appelé depuis l'origine staging : purge la base `staging` seulement, mais supprime **le compte Auth global** et **tout** `documents/{uid}/` du bucket partagé → les données Firestore **prod** (locataires, baux…) restent orphelines, sans `retentionUntil`. Les crons ne tournent que sur `(default)` : comptes anonymes de staging jamais purgés (Auth partagée), quittances de staging jamais purgées. Une origine staging non listée (ex. domaine par défaut `baillan-stage.web.app`) fait router les callables vers la **prod** alors que le client lit `staging`. |
| Impact | Racine de OWASP-01 ; effacement RGPD incomplet selon l'hôte utilisé ; surface d'attaque de production élargie à un front non relu. |
| Recommandation | Cible : projet Firebase distinct pour le staging (Auth, bucket, Functions, RevenueCat séparés). À défaut : restreindre le staging à une allowlist (custom claim `stagingTester` vérifié dans les règles de la base `staging` et dans `dbForRequest`), purger les deux bases dans `deleteAccount`, faire itérer les crons sur les deux bases, désactiver les domaines par défaut `*.web.app` du site staging. |

### OWASP-08 — Agent CI autonome alimenté par des issues potentiellement externes (injection de prompt)

| Champ | Contenu |
|---|---|
| Sévérité | **Moyenne** (**Élevée si le dépôt est public** — à confirmer) |
| Références | A08 Software & Data Integrity Failures |
| Fichiers | `.github/workflows/ticket-agent.yml:22-25`, `:58-70`, `:171-190` ; `.github/ISSUE_TEMPLATE/bug_report.yml:4`, `feature_request.yml:4` |
| Preuve | Les templates posent automatiquement `bug` / `feature-request` ; le job horaire sélectionne toute issue ouverte portant ces labels depuis plus de 3 h, **sans filtre sur l'auteur** (`author_association`), puis lance `claude-code-action` avec `contents: write`, `pull-requests: write`, `issues: write`, un `GH_TOKEN` et `CLAUDE_CODE_OAUTH_TOKEN`, en lui faisant lire le corps de l'issue. Le seul garde-fou est l'ajout manuel de `agent-skip` dans les 3 h. Protection des branches `main`/`develop` : « à configurer » selon `docs/GITFLOW.md:42` — à confirmer. |
| Impact | Si un tiers peut ouvrir une issue : instructions arbitraires exécutées par un agent disposant de droits d'écriture (poussée de branches, PR piégées, exfiltration de jetons, et — sans protection de `develop` — déploiement staging via `deploy.yml`). |
| Recommandation | Filtrer sur `author_association ∈ {OWNER, MEMBER, COLLABORATOR}` ou exiger un label `agent-approved` posé par un mainteneur ; réduire les permissions (`contents: read` + PR via jeton restreint) ; restreindre les outils de l'agent ; activer la protection de branches ; épingler les actions par SHA (cf. OWASP-16). |

### OWASP-09 — Dépendances Functions vulnérables ou obsolètes

| Champ | Contenu |
|---|---|
| Sévérité | **Moyenne** (exploitabilité réelle à confirmer) |
| Références | A06 Vulnerable & Outdated Components ; MASVS-CODE |
| Fichiers | `functions/package.json` (`firebase-admin ^12.7.0`, `firebase-functions ^6.0.1`, `stripe ^22.3.2`), `functions/package-lock.json` |
| Preuve | `npm audit --omit=dev` : 13 vulnérabilités (1 high, 12 moderate). High : `fast-xml-parser 5.9.3` (via `@google-cloud/storage`, GHSA-8r6m-32jq-jx6q). Moderate notables : `qs 6.15.3` (GHSA-4mjr-xmp4-gh2g DoS, GHSA-x5fp-wj9c-mxmx) et `body-parser 1.20.5` (GHSA-v422-hmwv-36x6) via `express 4.22.2` embarqué par `firebase-functions` — donc sur **tous** les endpoints HTTP/callables, avant authentification ; `protobufjs` DoS ; `uuid`. Versions : firebase-admin 12.7.0 (dernière 14.5.0), firebase-functions 6.6.0 (7.4.0). `site/` : 0 vulnérabilité. |
| Impact | Déni de service potentiel sur des endpoints publics ; retard de correctifs sur le SDK Admin. |
| Recommandation | `npm audit fix` (correctifs non cassants disponibles pour qs, body-parser, express, fast-xml-parser, protobufjs) ; planifier la montée firebase-admin 13/14 et firebase-functions 7 ; activer Dependabot (npm + pub + actions). |

### OWASP-10 — Champs d'abonnement `pro*` non gelés à la création du doc landlord

| Champ | Contenu |
|---|---|
| Sévérité | **Faible** |
| Références | A01 ; API3:2023 Broken Object Property Level Authorization |
| Fichiers | `firestore.rules:79-107` (et `:116-133` pour l'anonyme) ; `functions/src/entitlements/plan.ts:176-193` ; `functions/src/scheduled/reconcile_entitlements.ts:208-212` |
| Preuve | La création fige `subscriptionTier`, `planLevel`, `entitlements` et les compteurs, mais pas `proEntitlementActive`, `proExpiresAt`, `proLastEventAtMs`, `proStore`… ni la liste des clés (`hasOnly`). Or `legacyStates()` reconstruit un état `pro` **actif** à partir de `proEntitlementActive`/`proExpiresAt` quand la map `entitlements` est absente. Aucun test rules ne couvre ce cas à la création (les tests l. 359-379 ne couvrent que l'update). |
| Impact | Un compte peut s'injecter un état Pro fictif qui serait conservé par le webhook si un event RevenueCat arrive avant le passage du cron (qui le neutralise sous 24 h) ; un bourrage de comptes `proEntitlementActive: true` peut épuiser le lot `limit(200)` du cron et retarder la réconciliation des vrais abonnés. |
| Recommandation | À la création : exiger l'absence (ou la valeur neutre) de tous les champs `pro*` et ajouter `request.resource.data.keys().hasOnly([...])` ; tests rules correspondants. |

### OWASP-11 — `createDocument` : le rollback peut supprimer un fichier déjà référencé (y compris sous `legalHold`)

| Champ | Contenu |
|---|---|
| Sévérité | **Faible** |
| Références | A04 Insecure Design ; API3:2023 |
| Fichiers | `functions/src/callable/documents.ts:299-304`, `:395-399` |
| Preuve | Seul le préfixe `documents/{uid}/` est vérifié ; `storagePath` n'est lié ni au nouvel id ni à l'absence d'un autre document. Tout refus (ex. `leaseId` inexistant) déclenche `deleteStorageObject(storagePath)`. |
| Impact | Le bailleur peut détruire le fichier d'un de ses propres documents sous rétention légale (le doc Firestore subsiste, orphelin), ou référencer un même objet depuis deux documents. Pas d'impact inter-comptes. |
| Recommandation | Imposer `storagePath == documents/{uid}/{id}.{ext}` avec un id pré-alloué côté serveur, refuser si un document référence déjà ce chemin, et ne purger au rollback que les objets non référencés. |

### OWASP-12 — Politique de mot de passe serveur plus faible que la politique affichée

| Champ | Contenu |
|---|---|
| Sévérité | **Faible** |
| Références | A07 ; API2:2023 ; MASVS-AUTH |
| Fichiers | `lib/core/utils/password_validator.dart:25-28` ; `docs/SECURITY.md:142` |
| Preuve | Client : 8 caractères + lettre + chiffre. Serveur : plancher Firebase natif de 6 caractères, aucune password policy Identity Platform (documenté comme dette). |
| Impact | Comptes à mot de passe faible créables par appel direct à l'API Identity Toolkit. |
| Recommandation | Activer la password policy Identity Platform en mode « enforce » (aligner sur le client) ; vérifier la protection contre l'énumération d'emails (console, à confirmer). |

### OWASP-13 — Validation d'entrée sans bornes de taille

| Champ | Contenu |
|---|---|
| Sévérité | **Faible** |
| Références | A03 Injection (validation d'entrée) ; API4:2023 |
| Fichiers | `functions/src/callable/property_tenant.ts:100-101` (et tous les `requireString`/`optionalString`) ; `functions/src/callable/etat_des_lieux.ts:37-57`, `:83` ; `firestore.rules:436-438` (`paid_plan_interest.features is list`), `:453-466` (`support_requests.email` non lié au jeton) |
| Preuve | Aucun plafond de longueur sur noms, adresses, `filename`, commentaires, nombre de pièces/éléments d'état des lieux, liste `features`. `support_requests.email` accepte n'importe quelle adresse. |
| Impact | Documents gonflés jusqu'à 1 Mio (coût stockage/lecture, rendu PDF dégradé) ; demandes de support au nom d'une adresse tierce. Pas d'injection exploitable (Firestore paramétré, PDF sans interprétation HTML, aucun puits HTML côté Flutter). |
| Recommandation | Helper `requireString(value, name, {maxLength})` généralisé ; bornes sur tableaux ; `size()` dans les règles ; lier `support_requests.email` à `request.auth.token.email`. |

### OWASP-14 — Android : sauvegarde applicative non désactivée, repli de signature sur la clé debug

| Champ | Contenu |
|---|---|
| Sévérité | **Faible** |
| Références | MASVS-STORAGE, MASVS-CODE |
| Fichiers | `android/app/src/main/AndroidManifest.xml:2-5` ; `android/app/build.gradle.kts:59-66` |
| Preuve | Pas de `android:allowBackup="false"` ni de `dataExtractionRules` : le cache hors ligne Firestore (PII locataires) et la session Firebase entrent dans la sauvegarde cloud / le transfert d'appareil. La release est signée avec la clé debug si `key.properties` est absent. |
| Impact | Copie des données locales hors du périmètre maîtrisé ; risque de publier un binaire signé debug par erreur (refusé par Play, mais distribuable ailleurs). |
| Recommandation | `android:allowBackup="false"` (ou règles d'exclusion du cache Firestore et des prefs d'auth) ; faire échouer `assembleRelease` sans keystore. |

### OWASP-15 — Journalisation de sécurité et alerting insuffisants

| Champ | Contenu |
|---|---|
| Sévérité | **Faible** |
| Références | A09 Security Logging & Monitoring Failures |
| Fichiers | `functions/src/utils/callable_helpers.ts:170-181` ; callables (`permission-denied` levés sans log) ; `functions/src/http/revenuecat_webhook.ts:328` |
| Preuve | Les refus d'autorisation (tentatives d'IDOR) ne sont pas journalisés ; aucun alerting versionné (métriques de logs) sur les 401 du webhook, les échecs `reconcileEntitlements`, `[orphan-document]`, les suppressions de compte. Les journaux existants ne contiennent que des uid (pas de PII, pas de secret — point fort). |
| Impact | Détection tardive d'un abus (OWASP-01, 03, 04) ou d'une panne de facturation. |
| Recommandation | Log `warn` structuré (uid, fonction, motif) sur chaque `permission-denied` ; métriques de logs + alertes Cloud Monitoring sur ces événements. |

### OWASP-16 — Chaîne d'approvisionnement CI : actions épinglées par tag

| Champ | Contenu |
|---|---|
| Sévérité | **Faible** |
| Références | A08 Software & Data Integrity Failures |
| Fichiers | `.github/workflows/ticket-agent.yml:139`, `:162`, `:171` ; `.github/workflows/ci.yml:25` ; `.github/workflows/deploy.yml` |
| Preuve | `subosito/flutter-action@v2`, `anthropics/claude-code-action@v1`, `actions/*@v4` épinglés par tag mutable ; `ticket-agent.yml` n'épingle pas `flutter-version`. Le job de déploiement manipule `FIREBASE_SERVICE_ACCOUNT` (écrit dans un fichier, jamais affiché — correct). |
| Impact | Une action tierce compromise s'exécuterait avec le compte de service Firebase. |
| Recommandation | Épingler par SHA de commit (Dependabot `github-actions` pour les mises à jour). |

### OWASP-17 — Absence d'obfuscation et de contrôles d'intégrité mobile

| Champ | Contenu |
|---|---|
| Sévérité | **Info** |
| Références | MASVS-RESILIENCE |
| Fichiers | commandes de build (`docs/MOBILE.md`, `ios/fastlane/Fastfile`, `android/fastlane/Fastfile`) |
| Preuve | Pas de `--obfuscate --split-debug-info`, pas de détection root/jailbreak ni d'attestation (cf. OWASP-03). |
| Impact | Faible : l'autorité est côté serveur. |
| Recommandation | Obfuscation Dart en release ; l'attestation relève d'App Check. |

### OWASP-18 — Session web persistante sans expiration d'inactivité

| Champ | Contenu |
|---|---|
| Sévérité | **Info** |
| Références | A07 |
| Fichiers | `docs/SECURITY.md` (section « Session recovery ») ; `lib/features/auth/data/auth_repository.dart` |
| Preuve | Persistance IndexedDB par défaut, fin de session uniquement sur `signOut`. Choix documenté et déclaré dans la politique de confidentialité. |
| Recommandation | Envisager une expiration d'inactivité côté client pour les postes partagés ; les opérations sensibles exigent déjà une auth récente (point fort). |

### OWASP-19 — Rapports Crashlytics sans filtrage des données personnelles

| Champ | Contenu |
|---|---|
| Sévérité | **Info** |
| Références | MASVS-PRIVACY |
| Fichiers | `lib/core/observability/crash_reporting_service.dart` |
| Preuve | `recordError(error, stack)` transmet le message brut des exceptions (qui peut contenir des valeurs saisies ou des chemins). La collecte est opt-in et désactivée nativement par défaut (point fort). |
| Recommandation | Filtrer/normaliser les messages d'exception avant envoi. |

### OWASP-20 — SDK FlutterFire en retard d'une version majeure

| Champ | Contenu |
|---|---|
| Sévérité | **Info** (à confirmer) |
| Références | A06 ; MASVS-CODE |
| Fichiers | `pubspec.lock` (`firebase_core 3.15.2`, `firebase_auth 5.7.0`, `cloud_firestore 5.6.12`, `firebase_storage 12.4.10`, `cloud_functions 5.6.2`) |
| Preuve | Aucune base d'avis consultable hors ligne pour pub.dev ; `dart pub outdated` non exécuté (appel réseau). |
| Recommandation | Vérifier les avis de sécurité et planifier la montée FlutterFire. |

### OWASP-21 — Règles Storage sans tests automatisés

| Champ | Contenu |
|---|---|
| Sévérité | **Info** |
| Références | A05 ; A04 |
| Fichiers | `functions/rules-tests/` (seul `firestore_rules.test.ts`, 70 cas) ; `storage.rules` |
| Preuve | Aucun test ne couvre `storage.rules` ; la CI ne déploie `storage` que depuis `main`. |
| Recommandation | Ajouter une suite `@firebase/rules-unit-testing` Storage (anonyme, autre uid, taille, type, update/delete). |

---

## 3. Couverture par référentiel

### OWASP Top 10 (2021)

| ID | Statut | Justification |
|---|---|---|
| A01 Broken Access Control | Partiel | Cloisonnement inter-bailleurs solide ; OWASP-01 (tier prod via staging), OWASP-10. |
| A02 Cryptographic Failures | Conforme | TLS partout, hachage délégué à Firebase Auth, secrets en Secret Manager ; HSTS à confirmer. |
| A03 Injection | Conforme | Firestore paramétré, requête Stripe Search protégée par `assertSafeUid`, aucun puits HTML ; bornes manquantes (OWASP-13). |
| A04 Insecure Design | Partiel | OWASP-01, 03, 04, 05, 11. |
| A05 Security Misconfiguration | Partiel | En-têtes absents (OWASP-06), staging public adossé à la prod (OWASP-07). |
| A06 Vulnerable & Outdated Components | Partiel | 13 vulnérabilités npm Functions (OWASP-09) ; vitrine saine. |
| A07 Identification & Authentication Failures | Partiel | Email non vérifié côté serveur (OWASP-02), mot de passe 6 caractères (OWASP-12) ; ré-auth récente pour suppression/export correcte. |
| A08 Software & Data Integrity Failures | Partiel | Webhook authentifié (temps constant) ; agent CI (OWASP-08), actions non épinglées (OWASP-16). |
| A09 Security Logging & Monitoring Failures | Partiel | Journaux sans PII ni secret ; pas d'alerting ni de trace des refus (OWASP-15). |
| A10 SSRF | Conforme | Seules requêtes sortantes : Stripe SDK et API RevenueCat (uid encodé) ; aucune URL fournie par l'utilisateur. |

### OWASP API Security Top 10 (2023)

| ID | Statut | Justification |
|---|---|---|
| API1 BOLA | Conforme | Chaque id reçu (leaseId, propertyId, tenantId, paymentIds, documentId, expense id…) est rechargé et comparé à `request.auth.uid`. |
| API2 Broken Authentication | Partiel | OWASP-02 ; pas d'App Check (OWASP-03). |
| API3 BOPLA | Partiel | Gel des champs sensibles à l'update ; création landlord incomplète (OWASP-10), `storagePath` (OWASP-11). |
| API4 Unrestricted Resource Consumption | Non conforme | OWASP-03, 04, 13. |
| API5 BFLA | Conforme | Aucune fonction d'administration exposée ; actions Stripe restreintes sur mobile. |
| API6 Unrestricted Access to Sensitive Business Flows | Non conforme | OWASP-01. |
| API7 SSRF | Conforme | Idem A10. |
| API8 Security Misconfiguration | Partiel | OWASP-06 ; CORS ouvert des callables acceptable (jeton porteur, pas de cookie). |
| API9 Improper Inventory Management | Partiel | OWASP-07 (staging public partageant le backend prod). |
| API10 Unsafe Consumption of APIs | Partiel | Événements RevenueCat consommés sans contrôle d'environnement (OWASP-01). |

### OWASP MASVS v2

| Groupe | Statut | Justification |
|---|---|---|
| MASVS-STORAGE | Partiel | Préférences locales non sensibles ; sauvegarde Android non désactivée (OWASP-14). |
| MASVS-CRYPTO | Conforme | Aucune cryptographie maison ; primitives déléguées aux SDK et à TLS. |
| MASVS-AUTH | Partiel | Ré-auth avant suppression, révocation Apple (best-effort) ; OWASP-02, OWASP-12. |
| MASVS-NETWORK | Conforme | ATS iOS sans exception, pas de trafic en clair Android ; pas d'épinglage de certificat (acceptable). |
| MASVS-PLATFORM | Conforme | Une seule activité exportée (launcher), aucun deep link applicatif, schémas URL limités aux callbacks OAuth. |
| MASVS-CODE | Partiel | Drapeaux de test/émulateur compilés hors release (`kReleaseMode`/`kDebugMode`) ; dépendances (OWASP-09/20), signature debug en repli (OWASP-14). |
| MASVS-RESILIENCE | Non conforme (risque accepté) | Ni obfuscation ni attestation (OWASP-17, OWASP-03). |
| MASVS-PRIVACY | Partiel | Crashlytics opt-in désactivé par défaut, pas de SDK analytics ; OWASP-05, OWASP-19. |

---

## 4. Points forts vérifiés

- **Règles Firestore** : deny-by-default avec fallback `/{document=**}` ; `get` et `list` bornés à `isOwner(resource.data.landlordId)` sur toutes les collections métier ; créations cross-entity en `if false` (CF exclusives) ; quittances, décomptes et états des lieux immuables ; gel à l'update de `subscriptionTier`, `planLevel`, `entitlements`, compteurs de quota, champs `pro*`, `rgpdConsent*`, `createdAt`/`deletedAt`/`landlordId` ; borne `anonExpiresAt < now + 15 j`.
- **Callables** : uid dérivé uniquement de `request.auth` ; propriété et état actif re-vérifiés sur chaque identifiant reçu (aucun BOLA trouvé) ; quotas appliqués en transaction avec amorçage fail-closed des compteurs ; liste blanche des collections soft-deletables ; `legalHold` respecté par la suppression et la reclassification.
- **Stripe** : liste blanche d'origines à égalité stricte, regex localhost stricte (redirection ouverte corrigée), vérification du mode de la clé (`sk_live_`/`sk_test_`) sans repli sur la clé live, aucun identifiant Stripe accepté du client, `assertSafeUid` avant interpolation dans la requête Search, messages d'erreur Stripe jamais journalisés (`describeError`).
- **Webhook RevenueCat** : secret partagé comparé en temps constant, 401 sans détail, garde d'ordre par palier, entitlements inconnus ignorés, comptes anonymes ignorés, cron qui ne promeut jamais free → paid.
- **Actions sensibles** : `deleteAccount` et `exportAccountData` exigent une authentification de moins de 5 minutes, avec confirmation d'anonymat par l'Admin SDK (et non par le claim) ; résiliation Stripe avant purge.
- **Documents** : lecture Storage interdite, téléchargement par URL signée de 5 minutes sur un chemin issu de Firestore, taille réelle lue dans les métadonnées Storage, types MIME en liste blanche.
- **Secrets** : aucun motif de secret (Stripe, Resend, PAT GitHub, clé privée) dans l'arbre ni dans l'historique git ; `dart-defines.testlab.json` et journaux ignorés par git ; compte de service CI écrit dans un fichier, jamais affiché ; déploiements Firestore ciblés par base (`firestore:(default)` / `firestore:staging`).
- **Mobile** : émulateur, `MOBILE_STAGING` et auto-login Test Lab neutralisés en release ; sélection de la base `staging` gardée par `kIsWeb` ; Crashlytics désactivé nativement jusqu'au consentement.
- **RGPD** : consentement exigé par les règles à la création et version imposée côté serveur ; export couvrant les 11 collections et les singletons ; rétention des quittances avec purge automatique.
- **Vitrine** : site statique Astro, `npm audit` sans vulnérabilité.

---

## 5. Limites de l'audit

- **Aucun service déployé n'a été interrogé** : la configuration RevenueCat (envoi des events sandbox, intégration Stripe test, portée du webhook), le tableau de bord Stripe, et le comportement réel de l'API REST RevenueCat vis-à-vis des achats sandbox conditionnent l'exploitabilité exacte de OWASP-01 — **à confirmer**.
- **Console Firebase non vérifiée** : domaines autorisés, protection contre l'énumération d'emails, password policy, quotas d'inscription anonyme, App Check, CORS et cycle de vie du bucket, en-têtes réellement servis (HSTS), IAM du compte de service CI, contenu de Secret Manager.
- **GitHub non vérifié** : visibilité du dépôt et protection des branches (déterminent la sévérité de OWASP-08), secrets d'environnement.
- **Pas de test dynamique** (pentest, fuzzing des callables, charge) ni d'exécution des suites de tests.
- **Dépendances Flutter** : pas d'audit de vulnérabilités hors ligne pour pub.dev.
- **iOS** : réglages du projet Xcode (entitlements, protection des données) non audités en détail ; pas de binaire release analysé.
- Constats à confirmer : exploitabilité des CVE npm (OWASP-09), HSTS (OWASP-06), visibilité du dépôt (OWASP-08), comportement RevenueCat sandbox (OWASP-01).
