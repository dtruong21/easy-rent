# Historique des changements (état projet)

> **Fichier d'archive — NE PAS auto-charger.** Sorti de `INDEX.md` (diète tokens
> 2026-07-09) pour que le routeur d'état reste léger. À consulter uniquement
> pour l'historique détaillé d'une feature. Le statut courant vit dans
> [`FEATURES.md`](FEATURES.md) (matrice) ; les détails techniques dans les shards
> `schema/`, `functions/`, `routes/`.

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
- Coverage : toutes features bilingues. Note : flux suppression compte, e-mails, formatters dates/€ restent FR (post-M1).

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
