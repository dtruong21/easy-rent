# EasyRent — Backlog

Géré par `product-owner` et `feature-scout`. Détails dans `docs/backlog/<id>-<slug>.md`.

> Dernière mise à jour : 2026-05-28 (post merge FEAT-001 + validation staging bout-en-bout)

## En cours

_(rien encore)_

## Prochain (P0 — MVP, chaîne bloquante)

Ordonnées par dépendance. FEAT-003 et FEAT-004 sont parallélisables une fois FEAT-002 mergée.

| Ordre | ID | Titre | Dépend de | Story |
|---|---|---|---|---|
| 1 | FEAT-001 | Authentification magic link | — | [`backlog/001-auth-magic-link.md`](backlog/001-auth-magic-link.md) |
| 2 | FEAT-002 | Modèle de données & RLS (`landlords`, `properties`, `tenants`, `leases`) | FEAT-001 | [`backlog/002-data-model-rls.md`](backlog/002-data-model-rls.md) |
| 3 | FEAT-003 | CRUD biens immobiliers | FEAT-002 | [`backlog/003-crud-properties.md`](backlog/003-crud-properties.md) |
| 3 | FEAT-004 | CRUD locataires | FEAT-002 | [`backlog/004-crud-tenants.md`](backlog/004-crud-tenants.md) |
| 4 | FEAT-005 | CRUD baux (bien ↔ locataire) | FEAT-003, FEAT-004 | [`backlog/005-crud-leases.md`](backlog/005-crud-leases.md) |

```
FEAT-001 (auth)
    └── FEAT-002 (schéma + RLS)        ← fondation
            ├── FEAT-003 (properties)  ┐ parallélisables
            ├── FEAT-004 (tenants)     ┘
                    └── FEAT-005 (leases)
```

### Suite MVP non encore détaillée en stories (cf. `docs/ROADMAP.md`)

- Navigation principale (drawer + routes)
- FEAT-008 — Envoyer quittance par email (Resend / Edge Function)
- FEAT-009 — Upload & stockage de documents (Supabase Storage)
- FEAT-010 — Dashboard + polish PWA + déploiement prod

### Stories détaillées (P0 — à implémenter)

| Ordre | ID | Titre | Dépend de | Story |
|---|---|---|---|---|
| 6 | FEAT-006 | Enregistrer un paiement de loyer | FEAT-005 | [`backlog/006-payment-record.md`](backlog/006-payment-record.md) |
| 7 | FEAT-007 | Générer une quittance PDF de loyer (loi 6 juillet 1989) | FEAT-006 | [`backlog/007-quittance-pdf.md`](backlog/007-quittance-pdf.md) |
| 8 | FEAT-008 | Envoyer une quittance par email (Resend / Edge Function) | FEAT-007 | [`backlog/008-email-quittance.md`](backlog/008-email-quittance.md) |

> À détailler en stories lors du prochain `/discover` une fois la chaîne FEAT-001→005 entamée.

## Dette technique / risques identifiés (scout 2026-05-27)

- ✅ ~~`test/` absent~~ → résolu : scaffold `test/unit` + `test/widget` + étape `build_runner` ajoutée à la CI.
- ✅ ~~Pas de suite de tests RLS~~ → entamé : `supabase/tests/rls_landlords.sql` (à étendre par table au fil de FEAT-002+).
- **Aucun bucket Storage** configuré → bloque FEAT-009. À provisionner avant.
- **Aucune Edge Function** (`supabase/functions/` vide) → bloque FEAT-008 (Resend). Choisir le domaine email vérifié avant.
- **Pas de `seed.sql`** → données de dev locales manuelles pour l'instant.

### Setup infra déploiement — staging OK, prod à finir
- ✅ ~~`firebase.json` / `.firebaserc`~~ → posés (`build/web` + rewrites SPA pour GoRouter).
- ✅ ~~Secrets staging~~ : `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID` → posés sur env `staging`.
- ✅ ~~Provisionnement schéma `dev` pour QA staging~~ → fait via Supabase CLI (`supabase db push`).
- ✅ ~~Service worker piège-cache sur staging~~ → désactivé via `--pwa-strategy=none` dans `deploy.yml` quand env=staging.
- 🔧 **Environnement GitHub `production` à créer** (seul `staging` existe).
- 🔧 **Secrets prod manquants** : dupliquer `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `FIREBASE_SERVICE_ACCOUNT` / `FIREBASE_PROJECT_ID` sur env `production`. Plus ajouter `SUPABASE_PROJECT_REF`, `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` (utilisés par le job `apply-supabase-migrations` qui ne tourne que depuis `main`).
- 🔧 **Stratégie d'apply migrations à automatiser** : actuellement migrations posées sur dev via CLI manuelle. À terme : soit étendre `deploy.yml` pour appliquer aussi depuis `develop`, soit garder l'approche "1 fois par release depuis `main`". À trancher pendant FEAT-002.

### Gates AVANT mise en PROD (issus de l'audit sécu FEAT-001)
- ✅ ~~Redirect Allow-List Supabase~~ → configurée (Site URL + 3 variantes de redirect URLs pour staging, à ajouter pour prod plus tard).
- 🔧 **Compléter `/privacy`** : identité du responsable de traitement, DPO, base légale définitive de la persistance de session (placeholder actuellement).
- 🔧 **Seuils de rate-limit OTP** Supabase à vérifier en Studio.
- 🔧 **Reproduire URL Configuration Supabase pour le canal `live`** quand on déploiera en prod (Site URL + Redirect Allow-List).

### Items résolus par FEAT-002
- ✅ ~~FK `landlords.id … ON DELETE CASCADE`~~ → remplacé par `ON DELETE NO ACTION` (rétention 5 ans garantie). L'effacement RGPD passera par Edge Function dédiée (P1 ci-dessous).
- ✅ ~~Restriction colonne `deleted_at`~~ → trigger `prevent_protected_columns_change` (BEFORE INSERT OR UPDATE) sur 4 tables × 2 schémas ; soft-delete passe par RPC `soft_delete_*` SECURITY DEFINER.

### Dette tracée par FEAT-002 (P1)
- **Hardening flag de session GUC** : `app.allow_deleted_at_change` est aujourd'hui safe (PostgREST n'expose pas `set_config`) mais reste un footgun architectural. Remplacer par un mécanisme intransférable (ex: `pg_trigger_depth()` test, ou wrapping en fonction SECURITY DEFINER de niveau supérieur). Cf section "⚠️ Patterns sensibles" dans `docs/SECURITY.md`.
- **RGPD self-service** (P1) : export des données + droit à l'effacement (Edge Function qui anonymise plutôt qu'efface, conforme rétention 5 ans + RPC `soft_delete_*` cascade enfants).
- **`soft_delete_landlord` ne cascade pas vers properties/tenants/leases** : aujourd'hui un landlord soft-deleted laisse ses enfants visibles (deleted_at=NULL). Conforme RGPD rétention, mais incohérent UX si restauration future. À documenter ou à ajuster en P1.

## Plus tard (P1, P2)

Voir [`docs/ROADMAP.md`](ROADMAP.md) — charges récupérables, crédits, régularisation annuelle, état des lieux digital, rappels automatiques, export comptable (FEC), multi-utilisateurs, notifications push PWA, OCR, intégration bancaire.
