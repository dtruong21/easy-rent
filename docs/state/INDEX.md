# Project State Index

> **Snapshot vivant du projet EasyRent.** Maintenu par l'agent `state-keeper`. Source de vérité pour les agents — à lire AVANT de grep/scanner le codebase.

## Métadonnées

- **Dernière mise à jour** : 2026-06-25T20:00:00Z
- **Commit ref** : `a1fefec` (chore: Property.deletedAt + typed lease_form_page params + PaymentMethod sqlValue alignment)
- **Branche** : `chore/cleanup-tech-debt-and-docs-refresh-v2` (rebased sur develop)
- **Phase projet** : FEAT-001–016 ✅ mergées. MVP complet + FEAT-012/013/014/015/016 en production.

## Pointeurs

| Aspect du projet | Fichier |
|---|---|
| Schéma Postgres (tables, colonnes, RLS, fonctions) | [`SCHEMA.md`](SCHEMA.md) |
| Routes Flutter et widgets principaux | [`ROUTES.md`](ROUTES.md) |
| Features implémentées et statut | [`FEATURES.md`](FEATURES.md) |
| Dépendances (pubspec, Deno imports, CLI tools, hosting CSP) | [`DEPENDENCIES.md`](DEPENDENCIES.md) |
| Edge Functions déployées et planifiées | [`FUNCTIONS.md`](FUNCTIONS.md) |
| Material 3 theme config + dark mode fixes | [`THEME.md`](THEME.md) |

## Comment l'utiliser

**Tu es un agent IA travaillant sur EasyRent ?**

1. Lis ce fichier en premier. Repère la date de mise à jour.
2. Si la date est < 7 jours → fais confiance aux fichiers d'état listés ci-dessus.
3. Si la date est ≥ 7 jours OU manquante → flag-le à l'utilisateur et propose `/refresh-state` AVANT de continuer.
4. Ne grep/scan le codebase QUE si l'état ne couvre pas ton besoin.

**Économie attendue** : un agent qui consulte `SCHEMA.md` (200 tokens) au lieu de grep toutes les migrations (5000 tokens) divise sa consommation par 25.

## Quand mettre à jour cet état

- Après chaque feature mergée → `state-keeper` met à jour automatiquement
- Avant un sprint de features → `/refresh-state` pour reset propre
- Si un agent détecte une incohérence → flag immédiat à l'utilisateur

## Stack résumé

| Couche | Tech |
|---|---|
| Frontend | Flutter Web 3.x + Dart 3.11+ |
| State | Riverpod 2.6.0 |
| Navigation | GoRouter 14.6.0 + GoRouterRefreshStream (custom) |
| Auth | Supabase Auth (email + password, session PKCE recovery) — **pivot FEAT-011 2026-06-22** |
| Backend | Supabase (Postgres + Auth + Storage) |
| PDF | pdf + printing packages |
| Build | build_runner + freezed + json_serializable |
| Hosting | Firebase Hosting (staging ✅, prod ready) |
| CI/CD | GitHub Actions (ci.yml + deploy.yml + migrate-prod.yml) |

## Changements récents (2026-06-23 — 2026-06-25)

### FEAT-012 — Cards system (5 phases — Phase 0 ✅)
**Status** : ✅ DONE — toutes phases mergées (commits 2b7506b–9fdf647)

Refonte UI pages list (Properties, Tenants, Leases, Receipts) + dashboard polish :
- Phase 1 (FEAT-012 Phase 0+1) : Leases en cards `LeaseCard` avec badges status
- Phase 2 : Properties en cards `PropertyCard` avec address + type
- Phase 3 : Tenants en cards `TenantCard` avec nom + email + phone
- Phase 4 : Receipts timeline `ReceiptCard` avec PDF + share buttons
- Phase 5 : Dashboard polish design tokens (color, spacing, typography)

**Foundation** : `lib/core/ui/cards/` (EntityCard, StatusBadge, CardGrid)

### FEAT-013 — UX modernization (2 phases — ✅)
**Status** : ✅ DONE (commits 0e20c80, ae5fdf1)

- Phase 1 : AppAppBar standardisé + page transitions smooth (AppTransition enum)
- Phase 2 : Palette color modern indigo (replace teal) + Material 3 defaults

**Files** : `lib/core/ui/app_bar/app_app_bar.dart`, `lib/core/router/transitions.dart`

### FEAT-014 — Forms enrichment FR (4 phases — ✅)
**Status** : ✅ DONE (commits 4de7554–5f9cdfa — Phase 1–4 complets)

32 colonnes enrichies pour conformité location FR (DPE, étage, garant, IRL, dépôt de garantie, etc.)

| Phase | Table | Colonnes ajoutées | Migration |
|---|---|---|---|
| 1 | properties | rooms, bedrooms, floor, has_elevator, furnished, heating_type, dpe_letter, dpe_value_kwh_m2_year, ges_letter, construction_year, postal_code, city (12 total) | 20260622220000 |
| 2 | tenants | birth_date, birth_place, nationality, profession, employer, monthly_income_cents, previous_address, guarantor_name, guarantor_email, guarantor_phone (10 total) | 20260622230000 |
| 3 | leases | lease_type, deposit_amount_cents, payment_day, payment_method, irl_index_value, irl_quarter_ref, agency_fees_cents, solidarity_clause, entry_inventory_done (9 total) | 20260623000000 |
| 4 | payments | reference (1 total) | 20260623010000 |

### FEAT-015 — Detail pages enrichment
**Status** : ✅ DONE (commit 6959a9e)

Rendre visibles les champs FEAT-014 sur pages détail (PropertyDetailPage, TenantDetailPage, LeaseDetailPage). Finalisation StatusBadge migration (UI unifiée pour lease status).

### FEAT-016 — RGPD consent persistence
**Status** : ✅ DONE (commit e82d113 — migration 20260623020000)

Persistance consentement RGPD (accountability art. 7.1) :
- Colonnes : `landlords.rgpd_consent_at` (timestamptz NOT NULL), `landlords.rgpd_consent_version` (text NOT NULL)
- Backfill : comptes legacy = 'legacy-1', version = created_at
- Trigger `handle_new_user()` : lit `rgpd_consent_version` depuis raw_user_meta_data, fallback 'legacy-1'

## Audit incohérences (2026-06-25)

À la date 2026-06-25 (après merge FEAT-016, branche develop à 5f9cdfa) :

- **✅ Migrations cohérentes** : 16 fichiers SQL, toutes appliquées remote (fixtures visibles en Studio)
- **✅ Aucune route sans feature** : 18 routes GoRouter, 11 features implémentées
- **✅ Aucune table sans RLS** : landlords, properties, tenants, leases, payments, receipts, documents — 100% RLS + DEFAULT auth.uid() sur FK
- **✅ Aucune dépendance non déclarée** : pubspec.yaml à jour (Riverpod 2.6.0, GoRouter 14.6.0, freezed 2.5.7)
- **✅ Firestore CSP fixed** : fonts.gstatic.com dans firebase.json
- **✅ Edge Functions** : uniquement `generate-receipt` + `_shared` (send-receipt supprimée FEAT-008 pivot)

## Prochaines étapes (priorité)

- **Dépendances P2 backlog** : Riverpod 3.x, GoRouter 17.x, freezed 3.x (breaking changes — attendre sprint)
- **FEAT-012 Phase 1.5** : LeaseCard polish (dénormalisation loyer+charges dans la carte)
- **Staging dédié** : préparation déploiement channel staging (actuellement sur main)
- **Analytics avancées** (P1 post-MVP) : export comptable, vision Stripe/Brex (architecturale)
