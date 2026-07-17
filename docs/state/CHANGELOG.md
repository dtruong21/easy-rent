# Historique des changements (état projet)

> **Fichier d'archive — NE PAS auto-charger.** Sorti de `INDEX.md` (diète tokens
> 2026-07-09) pour que le routeur d'état reste léger. À consulter uniquement
> pour l'historique détaillé d'une feature. Le statut courant vit dans
> [`FEATURES.md`](FEATURES.md) (matrice) ; les détails techniques dans les shards
> `schema/`, `functions/`, `routes/`.

## Changements (2026-07-03 → 2026-07-17)

### PR #105 : Release — refus de taguer sans commit depuis le dernier tag — FIX (2026-07-17)
- **Bug** : pipeline de release **non idempotent**. `version.sh next auto` bumpait (patch) même avec **0 commit** dans le range depuis le dernier tag → un « Re-run all jobs » du deploy prod sur un SHA déjà publié créait un tag **neuf** + une GitHub Release au **changelog vide** (v1.0.0 → v1.0.1 → v1.0.2…). Le garde-fou `rev-parse --verify refs/tags/$TAG` (« existe déjà ») de `release.sh` ne pouvait **jamais** se déclencher dans le flux `auto` : le tag calculé était toujours neuf.
- **Correctif en deux points** : `release.sh` refuse de couper une release si le range est vide — signature greppable **« rien à publier »**, au point de mutation, à côté de son frère « existe déjà ». `version.sh` expose `pending` (nb de commits depuis le dernier tag) et ses `next`/`codename-next` ne bumpent plus sur range vide : ils rendent la version **déjà publiée**.
- **Contrainte structurante** (raison du découpage) : `version.sh next auto` est aussi appelé par le step « Determine version » de `deploy.yml` pour le **label du build prod**, *avant* le deploy. L'y faire échouer aurait cassé **tout le re-run** au lieu de le rendre bénin → le refus vit dans `release.sh`. Le re-build porte ainsi le bon label (`1.0.0`, et non une `1.0.1` fantôme) → re-run idempotent **de bout en bout**.
- `deploy.yml` : le step « Tag release » tolère « rien à publier » (`::warning`, run vert) comme re-run bénin, et continue de propager tout le reste avec son exit code (politique de PR #102, préservée).
- **Portée** : prod uniquement (`app_env == 'prod'`) → aucun effet sur staging. Ce chemin n'a **jamais tourné en CI** (`deploy.yml` versionné vit sur `develop`, qui ne déploie que staging) : première exécution au prochain `develop` → `main`.
- Vérifié en pilotant les vrais scripts dans un clone jetable **sans remote** : range vide → refus, aucun tag ; range non vide → tag toujours créé avec le bon bump (`feat` → minor, `fix`/`docs` → patch, `!` → major). Le dépôt a toujours **zéro tag** (correct : le versioning n'est pas encore publié sur `main`).
- Suite de **PR #102** (propagation des erreurs du step tag), dont le commentaire documentait ce bug comme « à traiter séparément » — commentaire mis à jour.
- Doc : `docs/VERSIONING.md` — « aucun commit depuis le dernier tag = aucune release ».

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
