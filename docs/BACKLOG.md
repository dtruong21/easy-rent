# EasyRent — Backlog

Géré par `product-owner` et `feature-scout`. Détails dans `docs/backlog/<id>-<slug>.md`.

> Dernière mise à jour : 2026-05-27 (via `/discover`)

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
- FEAT-006 — Enregistrer un paiement de loyer
- FEAT-007 — Générer quittance PDF (loi 6 juillet 1989)
- FEAT-008 — Envoyer quittance par email (Resend / Edge Function)
- FEAT-009 — Upload & stockage de documents (Supabase Storage)
- FEAT-010 — Dashboard + polish PWA + déploiement prod

> À détailler en stories lors du prochain `/discover` une fois la chaîne FEAT-001→005 entamée.

## Dette technique / risques identifiés (scout 2026-05-27)

- ✅ ~~`test/` absent~~ → résolu : scaffold `test/unit` + `test/widget` + étape `build_runner` ajoutée à la CI.
- ✅ ~~Pas de suite de tests RLS~~ → entamé : `supabase/tests/rls_landlords.sql` (à étendre par table au fil de FEAT-002+).
- **Aucun bucket Storage** configuré → bloque FEAT-009. À provisionner avant.
- **Aucune Edge Function** (`supabase/functions/` vide) → bloque FEAT-008 (Resend). Choisir le domaine email vérifié avant.
- **Pas de `seed.sql`** → données de dev locales manuelles pour l'instant.

### Gates AVANT mise en PROD (issus de l'audit sécu FEAT-001)
- 🔧 **Redirect Allow-List Supabase** : vérifier en Studio qu'aucun wildcard large n'est autorisé (sinon risque de capture de token magic link). Config, hors repo.
- 🔧 **Compléter `/privacy`** : identité du responsable de traitement, DPO, base légale définitive de la persistance de session (placeholder actuellement).
- 🔧 **Seuils de rate-limit OTP** Supabase à vérifier en Studio.

### À traiter en FEAT-002 (tracké depuis FEAT-001)
- **FK `landlords.id … ON DELETE CASCADE` vs rétention 5 ans** : remplacer par `ON DELETE RESTRICT`/`NO ACTION` + flux soft-delete applicatif **avant** d'introduire baux/quittances (sinon suppression de compte = effacement physique de données à conserver).
- **Restriction colonne `deleted_at`** : la policy UPDATE actuelle laisse le propriétaire modifier `deleted_at` ; restreindre via trigger `BEFORE UPDATE` (OLD/NEW).
- **RGPD self-service** (P1) : export des données + droit à l'effacement (Edge Function + exposition contrôlée de `deleted_at`).

## Plus tard (P1, P2)

Voir [`docs/ROADMAP.md`](ROADMAP.md) — charges récupérables, crédits, régularisation annuelle, état des lieux digital, rappels automatiques, export comptable (FEC), multi-utilisateurs, notifications push PWA, OCR, intégration bancaire.
