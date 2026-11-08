# Correctifs sécurité OWASP (audit du 2026-09-30) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corriger les constats OWASP-01, 05, 02, 04, 06 et 09 de l'audit `docs/security/owasp-audit-2026-09-30.md` (lire la section du constat avant chaque tâche).

**Architecture:** Correctifs ciblés, sans refonte : garde d'environnement sur le webhook de facturation, effacement RGPD complet, vérification d'email côté serveur (règles + callables), durcissement Storage, en-têtes HTTP, dépendances. App Check (OWASP-03) et l'isolation staging (OWASP-07) sont hors périmètre (chantiers séparés).

**Tech Stack:** Cloud Functions TS (firebase-functions v6, vitest, FakeFirestore), règles Firestore/Storage (tests `functions/rules-tests/` via émulateur), `firebase.json` Hosting, Flutter (client inchangé sauf nécessité).

## Global Constraints

- Lire la section du constat dans `docs/security/owasp-audit-2026-09-30.md` avant de commencer ; ne corriger **que** le constat de la tâche.
- Aucune régression fonctionnelle : inscription email/mot de passe, essai anonyme, passage anonyme → compte complet, Google/Apple, suppression et export du compte doivent continuer à marcher.
- Isolation prod/staging (ADR 0003) : jamais `admin.firestore()`/`getFirestore()` dans `functions/src/` hors `utils/db_router.ts`, crons et triggers ; `bash scripts/check-db-isolation.sh` vert.
- Aucun secret ni donnée personnelle dans les journaux (uid et compteurs seulement).
- Functions : dans `functions/`, avec Node 22 (`export PATH=/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:$PATH`) : `npm run lint`, `npm run build`, `npm test` ; règles : `npm run test:rules` (JDK : `export PATH="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin:$PATH"`).
- Flutter (si touché) : `export PATH=/opt/homebrew/bin:$PATH` ; `dart format` des fichiers touchés ; `flutter analyze` sans issue ; `flutter test` vert.
- TDD : test qui échoue d'abord, puis correctif.
- Commits : `git add` chemins explicites, jamais `-A` ; jamais `firebase.altports.local.json`. Fin de message : `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Aucun déploiement.

---

### Task 1: OWASP-01 — le mode test ne peut jamais accorder un palier en prod

**Files:** `functions/src/http/revenuecat_webhook.ts`, `functions/src/callable/create_checkout_session.ts`, `functions/src/scheduled/reconcile_entitlements.ts` (si concerné), tests associés dans `functions/src/__tests__/`.

- [ ] **Step 1: Garde d'environnement dans le webhook (TDD).** Ajouter `environment?: string` à `RcEvent`. Choisir la base **par l'environnement de l'event**, plus par `dbForLandlordUid` : `"SANDBOX"` → base `staging` uniquement ; `"PRODUCTION"` → base `(default)` uniquement ; absent ou autre valeur → event ignoré (`"ignored"`) et journalisé (uid + valeur, sans autre donnée). Dans la base choisie, doc landlord absent → `"no_landlord"` comme aujourd'hui (jamais de repli sur l'autre base). Obtenir les bases via les helpers de `utils/db_router.ts` (ajouter un helper exporté si nécessaire, ex. `dbForEnv(isStaging)`), pas de `getFirestore()` direct. Tests : SANDBOX + doc seulement en prod → rien écrit en prod ; SANDBOX + doc en staging → staging mis à jour ; PRODUCTION + doc en prod → prod mis à jour ; PRODUCTION + doc seulement en staging → rien ; environnement absent → ignoré ; event `TEST` inchangé.
- [ ] **Step 2: Checkout.** Dans `createCheckoutSession`, refuser (`failed-precondition`, `landlord_not_found`) quand le doc `landlords/{uid}` est **absent** de la base routée (aujourd'hui `assertCanOpenCheckout(null)` laisse passer). Tests : doc absent → refus sans appel Stripe ; doc présent → comportement inchangé.
- [ ] **Step 3: Cron.** Lire `reconcile_entitlements.ts` : s'il peut **accorder** ou **prolonger** un palier à partir des données RevenueCat, ignorer les entitlements d'achats sandbox pour la base `(default)` (champ `is_sandbox` / environnement de l'API REST). S'il ne fait que rétrograder, ne rien changer et le noter dans le rapport.
- [ ] **Step 4: Vérifier et committer** (`fix(billing): un achat en mode test ne peut plus accorder un palier en prod`).

### Task 2: OWASP-05 — effacement RGPD complet

**Files:** `functions/src/callable/delete_account.ts`, `functions/src/callable/export_account_data.ts` (lecture pour la parité), tests, `docs/LEGAL.md` si la promesse change.

- [ ] **Step 1: Purge.** Ajouter `charge_statements` et `etat_des_lieux` à `PURGED_COLLECTIONS` (hard-delete, conforme à `docs/LEGAL.md:35` « tout le reste est hard-delete immédiat »). Vérifier où sont stockés leurs PDF éventuels (Storage) et purger ces préfixes s'ils sont hors de `documents/{uid}/`.
- [ ] **Step 2: Test de parité.** Test qui échoue si une collection exportée par `exportAccountData` n'est ni purgée ni explicitement retenue (`receipts`), pour que toute future collection soit couverte. Tests de purge des deux nouvelles collections.
- [ ] **Step 3: Vérifier et committer** (`fix(rgpd): la suppression du compte efface décomptes de charges et états des lieux`). Signaler dans le rapport que les comptes déjà supprimés peuvent avoir laissé des docs (script ponctuel hors périmètre).

### Task 3: OWASP-02 — email vérifié exigé côté serveur

**Files:** `firestore.rules`, `functions/rules-tests/firestore_rules.test.ts`, `functions/src/utils/callable_helpers.ts`, callables métier, tests.

- [ ] **Step 1: Règles (TDD).** `isFullyAuthed()` exige en plus `request.auth.token.email_verified == true || request.auth.token.firebase.sign_in_provider in ['google.com', 'apple.com']`. **Exception obligatoire** : la création du doc `landlords/{uid}` par son propriétaire à l'inscription se fait **avant** la vérification (`auth_repository.dart` `signUpWithPassword`) — vérifier la règle de création et la garder possible pour un compte non vérifié (propre doc, champs contraints comme aujourd'hui). Tests règles : non vérifié → lecture/écriture métier refusées ; vérifié, Google, Apple → autorisées ; création du doc landlord à l'inscription non vérifiée → autorisée ; anonyme → comportement inchangé.
- [ ] **Step 2: Callables.** Helper `requireVerifiedUid(request)` : accepte un compte anonyme (règles d'essai inchangées) ou un compte avec email vérifié / Google / Apple ; sinon `failed-precondition`, `email_not_verified`. L'appliquer aux callables métier. **Exemptés** : `deleteAccount`, `exportAccountData`, `finalizeAnonymousUpgrade` (appelé **avant** la vérification lors du passage anonyme → compte complet, cf. `auth_repository.dart:165-176`). Tests du helper et d'au moins deux callables.
- [ ] **Step 3: Client.** Vérifier que l'app ne mappe pas `failed-precondition` d'une callable métier sur une erreur trompeuse ; sinon, message clair (l10n FR/EN).
- [ ] **Step 4: Vérifier (y compris `npm run test:rules`) et committer** (`fix(auth): email vérifié exigé par les règles et les callables`).

### Task 4: OWASP-04 — Storage durci

**Files:** `storage.rules`, tests de règles Storage (nouveaux), `functions/src/scheduled/cleanup_expired_anon.ts`, tests.

- [ ] **Step 1: Règles (TDD).** Écriture sous `documents/{landlordId}/…` : propriétaire, **non anonyme**, email vérifié (même condition que Task 3), nom d'objet contraint au format réellement produit par le client (lire `upload_documents_drop_zone.dart`, `expense_receipt_field.dart` et le repository d'upload pour le chemin exact), taille et type inchangés. Lecture inchangée.
- [ ] **Step 2: Tests de règles Storage.** Étendre l'outillage `test:rules` à l'émulateur Storage (`--only firestore,storage`) avec un fichier de tests dédié : anonyme refusé, autre bailleur refusé, nom hors format refusé, trop gros refusé, cas nominal accepté.
- [ ] **Step 3: Purge des anonymes.** `cleanupExpiredAnon` supprime aussi `documents/{uid}/` des comptes anonymes expirés. Test.
- [ ] **Step 4: Vérifier et committer** (`fix(storage): téléversements réservés aux comptes vérifiés, anonymes purgés`). La purge des objets orphelins (non référencés) reste hors périmètre (issue).

### Task 5: OWASP-06 + OWASP-09 — en-têtes HTTP et dépendances

**Files:** `firebase.json`, `functions/package.json`, `functions/package-lock.json`.

- [ ] **Step 1: En-têtes.** Sur les 4 cibles Hosting (app prod, app staging, vitrine prod, vitrine staging), bloc `source: "**"` : `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()` (vérifier qu'aucune fonction de l'app ne les utilise), `X-Frame-Options: DENY`. CSP : **vitrine** en CSP appliquée (`default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self'; script-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'` — vérifier contre `site/dist` : aucun script exécutable, styles inline Astro) ; **app Flutter** : `Content-Security-Policy: frame-ancestors 'none'` appliqué + une CSP complète en `Content-Security-Policy-Report-Only` (Flutter/CanvasKit : `'wasm-unsafe-eval'`, `https://www.gstatic.com`, endpoints Firebase/Google/Stripe en `connect-src`). Ne pas casser les règles de cache existantes (dernière règle correspondante gagne par en-tête). Valider que `firebase.json` reste un JSON valide.
- [ ] **Step 2: Dépendances.** Dans `functions/` : `npm audit fix` **sans** `--force` ; relancer lint/build/test ; `npm audit --omit=dev` après coup dans le rapport. Pas de montée majeure (firebase-admin 13/14, firebase-functions 7 → issue).
- [ ] **Step 3: Vérifier et committer** (deux commits : `fix(hosting): en-têtes de sécurité HTTP` et `fix(deps): correctifs npm audit des Functions`).

### Task 6: Documentation et état projet

**Files:** `docs/security/owasp-audit-2026-09-30.md` (ajouter un statut « corrigé » par constat traité, avec le commit), `docs/SECURITY.md` (renvoi vers l'audit), `docs/LEGAL.md` (si Task 2 l'exige), shards `docs/state/functions/*` et `docs/state/schema/*` concernés, `docs/state/CHANGELOG.md`.

- [ ] **Step 1:** Mettre à jour les documents (faits vérifiés dans le code, rien d'inventé). Mentionner : redéploiement des Functions requis ; règles Firestore/Storage déployées par la CI (`firestore:staging`) ou à la main ; action manuelle RevenueCat recommandée (webhook prod « Production only » si l'option existe).
- [ ] **Step 2: Commit** (`docs(security): statut des correctifs OWASP du 2026-09-30`), en incluant le rapport d'audit.
