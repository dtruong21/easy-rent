# Schéma Postgres — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/migrations/`. **Dernière sync** : 2026-06-02 (FEAT-009 — table documents + enum document_category + bucket Storage documents + RPC soft_delete_document)

## Tables

### `landlords` (public + dev)

**Migration source** : `20260527081533_feat001_landlords_auth.sql` (création), `20260528120000_feat002_data_model.sql` (extension)

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, FK → `auth.users(id)` ON DELETE NO ACTION |
| `email` | `text` | NOT NULL |
| `full_name` | `text` | NULL — rempli dans les paramètres (FEAT-003+) |
| `phone` | `text` | NULL |
| `address` | `text` | NULL |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() (trigger `tr_02_set_updated_at_landlords`) |
| `deleted_at` | `timestamptz` | NULL — soft-delete. Modifiable uniquement via `soft_delete_landlord()` RPC |

**Index** : `idx_public_landlords_email` (public + dev)

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `landlord_selects_self` | SELECT | `id = auth.uid() AND deleted_at IS NULL` |
| `landlord_updates_self` | UPDATE | USING: `id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `id = auth.uid()` |

**Client constraints** :
- INSERT : **interdit** (aucune policy INSERT → trigger `handle_new_user()` insère auto)
- DELETE : **interdit** (soft-delete via RPC `soft_delete_landlord()`)

---

### `properties` (public + dev)

**Migration source** : `20260528120000_feat002_data_model.sql`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `landlord_id` | `uuid` | FK → `landlords(id)` ON DELETE RESTRICT |
| `name` | `text` | NOT NULL, CHECK length > 0 |
| `address` | `text` | NOT NULL, CHECK length > 0 |
| `type` | `text` | NOT NULL, CHECK IN ('appartement', 'maison', 'studio', 'autre') |
| `surface_m2` | `numeric(6,2)` | NULL, CHECK > 0 (si renseigné) |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC `soft_delete_property()` |

**Index** : `idx_public_properties_landlord_id`, `idx_dev_properties_landlord_id`

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `properties_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `properties_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |
| `properties_update_own` | UPDATE | USING: `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `landlord_id = auth.uid()` |

---

### `tenants` (public + dev)

**Migration source** : `20260528120000_feat002_data_model.sql`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `landlord_id` | `uuid` | FK → `landlords(id)` ON DELETE RESTRICT |
| `first_name` | `text` | NOT NULL, CHECK length > 0 |
| `last_name` | `text` | NOT NULL, CHECK length > 0 |
| `email` | `text` | NOT NULL, CHECK regex `^[^@\s]+@[^@\s]+\.[^@\s]+$` |
| `phone` | `text` | NULL |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC `soft_delete_tenant()` |

**Index** : `idx_public_tenants_landlord_id`, `idx_dev_tenants_landlord_id`

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `tenants_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `tenants_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |
| `tenants_update_own` | UPDATE | USING: `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `landlord_id = auth.uid()` |

---

### `leases` (public + dev)

**Migration source** : `20260528120000_feat002_data_model.sql`

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `landlord_id` | `uuid` | FK → `landlords(id)` ON DELETE RESTRICT (dénormalisé pour RLS) |
| `property_id` | `uuid` | FK → `properties(id)` ON DELETE RESTRICT |
| `tenant_id` | `uuid` | FK → `tenants(id)` ON DELETE RESTRICT |
| `rent_amount_cents` | `integer` | NOT NULL, CHECK > 0 (en centimes, ex: 85000 = 850,00€) |
| `charges_amount_cents` | `integer` | NOT NULL DEFAULT 0, CHECK >= 0 |
| `start_date` | `date` | NOT NULL |
| `end_date` | `date` | NULL (= CDI), CHECK end_date > start_date (si renseigné) |
| `status` | `text` | NOT NULL DEFAULT 'active', CHECK IN ('active', 'terminated', 'archived') |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC `soft_delete_lease()` |

**Index** : `idx_public_leases_landlord_id`, `idx_public_leases_property_id`, `idx_public_leases_tenant_id`, `idx_public_leases_status_active_partial` (WHERE status='active' AND deleted_at IS NULL) + équivalents dev

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `leases_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `leases_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |
| `leases_update_own` | UPDATE | USING: `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `landlord_id = auth.uid()` |

---

### `documents` (public + dev)

**Migration source** : `20260602100520_feat009_documents.sql` (FEAT-009)

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` ON DELETE RESTRICT (dénormalisé pour RLS) |
| `lease_id` | `uuid` | NOT NULL, FK → `leases(id)` ON DELETE RESTRICT |
| `category` | `public.document_category` | NOT NULL — enum (bail_signe, etat_des_lieux, attestation_assurance, quittance_scannee, autre) |
| `filename` | `text` | NOT NULL, CHECK char_length BETWEEN 1 AND 255 |
| `storage_path` | `text` | NOT NULL UNIQUE, CHECK char_length BETWEEN 1 AND 500 |
| `mime_type` | `text` | NOT NULL, CHECK IN ('application/pdf', 'image/jpeg', 'image/png', 'image/webp') |
| `size_bytes` | `integer` | NOT NULL, CHECK BETWEEN 1 AND 10485760 (10 MB max) |
| `legal_hold` | `boolean` | NOT NULL DEFAULT false — calculé par trigger tr_00b : true ssi category IN ('bail_signe', 'etat_des_lieux'). Immuable après INSERT |
| `uploaded_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() (trigger `tr_02_set_updated_at_documents`) |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC `soft_delete_document()` uniquement |

**Nouveau type** : `public.document_category` + `dev.document_category` — ENUM (`bail_signe`, `etat_des_lieux`, `attestation_assurance`, `quittance_scannee`, `autre`)

**Index** :
- `idx_public_documents_lease (landlord_id, lease_id, deleted_at)` — listing par bail
- `idx_public_documents_landlord (landlord_id, deleted_at)` — quota global landlord
- `idx_public_documents_storage_path (storage_path) WHERE deleted_at IS NULL` — lookup soft-delete aware (UNIQUE partial)
- Équivalents `idx_dev_documents_*`

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `documents_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `documents_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |
| `documents_update_category_only` | UPDATE | USING: `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `landlord_id = auth.uid()` |

**Pas de policy DELETE** : soft-delete via RPC `soft_delete_document()` uniquement.

**Triggers** :
- `tr_00_assert_documents_lease_ownership` BEFORE INSERT (ownership, SECURITY DEFINER)
- `tr_00b_compute_legal_hold` BEFORE INSERT (calcul legal_hold depuis category)
- `tr_01_prevent_protected_columns_change_documents` BEFORE INSERT OR UPDATE (réutilise FEAT-002)
- `tr_01b_protect_immutable_documents` BEFORE UPDATE (protège filename, storage_path, mime_type, size_bytes, legal_hold — aucun GUC bypass)
- `tr_02_set_updated_at_documents` BEFORE UPDATE (réutilise FEAT-001)

---

### `receipts` (public + dev)

**Migration source** : `20260531172904_feat007_receipts.sql` (FEAT-007), `20260601103751_feat008_email_quittance.sql` (FEAT-008)

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` ON DELETE RESTRICT (dénormalisé pour RLS) |
| `lease_id` | `uuid` | NOT NULL, FK → `leases(id)` ON DELETE RESTRICT |
| `payment_ids` | `uuid[]` | NOT NULL, CHECK array_length >= 1 |
| `period_start` | `date` | NOT NULL, CHECK BETWEEN 1900-01-01..2100-12-31 |
| `period_end` | `date` | NOT NULL, CHECK > period_start AND BETWEEN bornes |
| `rent_cents` | `integer` | NOT NULL, CHECK > 0 (en centimes) |
| `charges_cents` | `integer` | NOT NULL DEFAULT 0, CHECK >= 0 (en centimes) |
| `total_cents` | `integer` | NOT NULL, CHECK > 0 AND CHECK = rent_cents + charges_cents |
| `document_type` | `public.document_type` | NOT NULL — enum `quittance` ou `recu` |
| `pdf_path` | `text` | NOT NULL — chemin Storage `receipts/<landlord_id>/<receipt_id>.pdf` |
| `generated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `is_voided` | `boolean` | NOT NULL DEFAULT false |
| `voided_at` | `timestamptz` | NULL (doit être non-NULL si is_voided = true) |
| `voided_reason` | `text` | NULL, CHECK char_length BETWEEN 3 AND 500 (obligatoire si voided) |
| `is_stale` | `boolean` | NOT NULL DEFAULT false — recomputed par trigger tr_03 |
| `sent_at` | `timestamptz` | NULL = jamais envoyé. Audit trail email. Modifiable uniquement via `mark_receipt_as_sent` RPC. FEAT-008. |
| `sent_to_email` | `text` | NULL si `sent_at IS NULL`. Snapshot email destination au moment de l'envoi. CHECK char_length BETWEEN 3 AND 255. Modifiable uniquement via `mark_receipt_as_sent` RPC. FEAT-008. |

**Contraintes** :
- `receipts_total_check` : `total_cents = rent_cents + charges_cents`
- `receipts_voiding_consistency` : `(is_voided=false AND voided_at IS NULL AND voided_reason IS NULL) OR (is_voided=true AND voided_at IS NOT NULL AND voided_reason IS NOT NULL)`
- `receipts_sent_consistency` : `(sent_at IS NULL AND sent_to_email IS NULL) OR (sent_at IS NOT NULL AND sent_to_email IS NOT NULL AND char_length(sent_to_email) BETWEEN 3 AND 255)` — FEAT-008
- Pas de `updated_at` ni `deleted_at` : document immuable hors flags

**Indexes** :
- `idx_public_receipts_landlord_id` (filtrage RLS)
- `idx_public_receipts_lease_id` (listing par bail)
- `idx_public_receipts_period_start_desc` (lease_id, period_start DESC)
- `idx_public_receipts_payment_ids_gin` USING GIN (payment_ids — trigger is_stale)
- Équivalents `idx_dev_receipts_*`

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `receipts_select_own` | SELECT | `landlord_id = auth.uid()` (toutes receipts y compris voided) |
| `receipts_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |

**Pas de policy UPDATE ni DELETE** : immuabilité des champs métier ; voiding uniquement via RPC `void_receipt`.

**Triggers** :
- `tr_00_assert_receipt_lease_ownership` BEFORE INSERT (ownership, SECURITY DEFINER)
- `tr_01_prevent_protected_columns_change_receipts` BEFORE INSERT OR UPDATE (réutilise FEAT-002)
- `tr_01b_protect_sent_columns_receipts` BEFORE UPDATE (protège sent_at + sent_to_email — dédié FEAT-008, GUC app.allow_sent_columns_change)
- Pas de tr_02 (pas de updated_at)
- `tr_03_set_receipt_stale_on_payment_archive` sur public.payments + dev.payments AFTER UPDATE OF deleted_at

---

### `payments` (public + dev)

**Migration source** : `20260531102202_feat006_payments.sql` (890 lignes)

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `lease_id` | `uuid` | FK → `leases(id)` ON DELETE RESTRICT |
| `landlord_id` | `uuid` | FK → `landlords(id)` ON DELETE RESTRICT (dénormalisé pour RLS) |
| `period_start` | `date` | NOT NULL, CHECK BETWEEN 1900-01-01..2100-12-31 |
| `period_end` | `date` | NOT NULL, CHECK > period_start AND BETWEEN 1900-01-01..2100-12-31 |
| `paid_at` | `date` | NOT NULL (autorisée futur), CHECK BETWEEN 1900-01-01..2100-12-31 |
| `rent_amount_cents` | `integer` | NOT NULL, CHECK > 0 (en centimes, ex: 85000 = 850,00€) |
| `charges_amount_cents` | `integer` | NOT NULL DEFAULT 0, CHECK >= 0 (en centimes) |
| `payment_method` | `text` | NOT NULL, CHECK IN ('virement', 'cheque', 'especes', 'prelevement', 'autre') |
| `notes` | `text` | NULL, CHECK length <= 500 |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC `soft_delete_payment()` |

**Index** :
- `idx_public_payments_landlord_id` (RLS filtrage auth.uid())
- `idx_public_payments_lease_id` (listage paiements d'un bail)
- `idx_public_payments_period_start_desc` (tri par période décroissante)
- `idx_public_payments_active_partial` (WHERE deleted_at IS NULL, requête la plus fréquente)
+ équivalents dev

**RLS** : activée

**Policies** (public + dev) :

| Policy | Opération | Condition |
|---|---|---|
| `payments_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `payments_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |
| `payments_update_own` | UPDATE | USING: `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `landlord_id = auth.uid()` |

**Notes** :
- Pas de policy DELETE (soft-delete via RPC uniquement)
- Aucune UNIQUE sur (lease_id, period_start, period_end) — doublons autorisés (régularisations)
- FK lease_id RESTRICT : impossible de supprimer un bail avec des paiements

---

## Triggers et fonctions Postgres

### Fonctions helper (debug, init)

**`dev.check_schema_parity()`** — Compares tables between `public` et `dev` schémas. FEAT-001.

**`dev.assert_rls_both_schemas(table_name text)`** — Assert RLS activée sur table dans les deux schémas. FEAT-002.

---

### Fonctions de sécurité

**`public.prevent_protected_columns_change()`** — Trigger BEFORE INSERT OR UPDATE (réutilisable, 4 tables × 2 schémas)

- **À l'INSERT** :
  - Bloque `deleted_at` ≠ NULL sauf flag `app.allow_deleted_at_change = '1'` (réservé aux RPC)
  - Force `created_at := now()` et `updated_at := now()` (pragmatique — corrige les antidates silencieusement)
- **À l'UPDATE** :
  - Bloque modification de `deleted_at` sauf flag (ERRCODE 42501)
  - Bloque modification de `created_at` (immuable, ERRCODE 42501)
  - Force `updated_at := OLD.updated_at` (repris par tr_02)

**`public.assert_lease_ownership_consistency()`** — Trigger BEFORE INSERT OR UPDATE sur `public.leases`, SECURITY DEFINER, SET search_path = public

- Valide que `property_id` existe
- Valide que `tenant_id` existe
- Valide que `property_id.landlord_id` = `NEW.landlord_id`
- Valide que `tenant_id.landlord_id` = `NEW.landlord_id`
- ERRCODE 23514 (check_violation)
- Bypass RLS intentionnellement pour voir toutes les lignes (cohérence cross-FK)

**`dev.assert_lease_ownership_consistency()`** — Mirror DEV (SET search_path = dev, lit dev.properties et dev.tenants)

**`public.assert_payment_lease_ownership()`** — Trigger BEFORE INSERT OR UPDATE sur `public.payments`, SECURITY DEFINER, SET search_path = public (FEAT-006)

- Valide que `lease_id` existe dans `public.leases`
- Valide que `lease_id.landlord_id` = `NEW.landlord_id`
- ERRCODE 23514 (check_violation)
- Bypass RLS intentionnellement pour voir toutes les lignes (cohérence cross-FK)

**`dev.assert_payment_lease_ownership()`** — Mirror DEV (SET search_path = dev, lit dev.leases)

---

### Fonctions d'auto-provisioning et maintenance

**`public.handle_new_user()`** — Trigger AFTER INSERT ON `auth.users`, SECURITY DEFINER, SET search_path = public

- Insère une ligne dans `public.landlords` ET `dev.landlords` à chaque signup
- Idempotent (ON CONFLICT DO NOTHING)
- FEAT-001

**`public.set_updated_at()`** — Trigger BEFORE UPDATE, maintient `updated_at = now()`

- Attaché à `public.landlords` (tr_02), `public.properties` (tr_02), `public.tenants` (tr_02), `public.leases` (tr_02) + équivalents dev
- FEAT-001 (créée FEAT-002 a renommé le trigger sur landlords pour respect de l'ordre alphabétique tr_01 < tr_02)

---

### RPC SECURITY DEFINER — soft-delete

Chacune pose `SET LOCAL app.allow_deleted_at_change = '1'` (scope transaction) pour contourner le trigger `tr_01`. Ownership check (`landlord_id = auth.uid()`) dans le WHERE. Aucune policy DELETE sur aucune table.

**`public.soft_delete_landlord()`** — Soft-delete du landlord courant (auth.uid()). FEAT-002.

**`public.soft_delete_property(p_id uuid)`** — Soft-delete property (vérifie ownership). FEAT-002.

**`public.soft_delete_tenant(p_id uuid)`** — Soft-delete tenant (vérifie ownership). FEAT-002.

**`public.soft_delete_lease(p_id uuid)`** — Soft-delete lease (vérifie ownership). FEAT-002.

**`public.soft_delete_payment(p_id uuid)`** — Soft-delete payment (vérifie ownership `landlord_id = auth.uid()` AND deleted_at IS NULL). FEAT-006.

**Versions dev** : `dev.soft_delete_landlord()`, `dev.soft_delete_property()`, `dev.soft_delete_tenant()`, `dev.soft_delete_lease()`, `dev.soft_delete_payment()` — mêmes signatures, opèrent sur schéma `dev`.

---

## Triggers ordre d'exécution

PG exécute BEFORE INSERT OR UPDATE dans l'ordre alphabétique du nom. Ordre garanti :

1. **`tr_00_assert_*_ownership`** (leases + payments) — Validation cross-FK
   - `tr_00_assert_lease_ownership` (leases)
   - `tr_00_assert_payment_lease_ownership` (payments, FEAT-006)
2. **`tr_01_prevent_protected_columns_change_*`** (toutes les 5 tables) — Bloque deleted_at, created_at ; force updated_at
   - landlords, properties, tenants, leases, payments (FEAT-006)
3. **`tr_02_set_updated_at_*`** (toutes les 5 tables sauf si DELETE) — Remet à jour updated_at
   - landlords, properties, tenants, leases, payments (FEAT-006)

---

## Schémas

### `public` (PROD)

- Status : Initialized by Supabase (default)
- RLS : enabled per table
- Roles : `authenticated`, `anon`, `service_role`

### `dev` (DEV)

- Status : créé via migration init
- RLS : enabled per table
- Roles : `authenticated`, `anon`, `service_role`
- Default privileges : `SELECT, INSERT, UPDATE, DELETE` sur tables pour `authenticated`
- Comment : "Development/staging mirror of public schema. Mapped to Git branch `develop`."

---

## Résumé des changements FEAT-008 (Phase 1 — SQL)

**Migration** : `20260601103751_feat008_email_quittance.sql`

**Colonnes ajoutées à `receipts`** (public + dev) :
- `sent_at timestamptz NULL` — audit trail email, NULL = jamais envoyé
- `sent_to_email text NULL` — snapshot email destination au moment de l'envoi

**Contrainte** : `receipts_sent_consistency` CHECK — sent_at et sent_to_email sont NULL ensemble ou non-NULL ensemble (+ char_length 3..255)

**Nouveau trigger** (public + dev) : `tr_01b_protect_sent_columns_receipts` BEFORE UPDATE — protège sent_at et sent_to_email contre toute écriture directe hors RPC. Mécanisme GUC `app.allow_sent_columns_change = '1'`.

**Nouvelle RPC** (public + dev) : `mark_receipt_as_sent(p_receipt_id uuid, p_sent_to_email text) RETURNS receipts` — SECURITY DEFINER, SET search_path = public/dev, REVOKE anon. Vérifie ownership + is_voided=false + is_stale=false. Pose le flag GUC. Idempotent (2e appel écrase). ERRCODE 22023 si email invalide, P0002 si not found/voided/stale/cross-user.

**RLS** : inchangée (pas de nouvelle policy — l'immuabilité document reste garantie par l'absence de policy UPDATE ; la RPC est SECURITY DEFINER).

**Tests** : `supabase/tests/rls_receipts_send.sql` (14 tests)

---

## Résumé des changements FEAT-009 (SQL — couche données + Storage)

**Migration** : `20260602100520_feat009_documents.sql`

**Nouveau type** : `public.document_category` + `dev.document_category` — ENUM (`bail_signe`, `etat_des_lieux`, `attestation_assurance`, `quittance_scannee`, `autre`)

**Nouvelles tables** : `documents` (public + dev) — Documents locatifs uploadés par le bailleur

**Trigger framework** :
- `tr_00_assert_documents_lease_ownership` BEFORE INSERT (ownership, SECURITY DEFINER)
- `tr_00b_compute_legal_hold` BEFORE INSERT (calcule legal_hold depuis category — D3 modifié)
- `tr_01_prevent_protected_columns_change_documents` BEFORE INSERT OR UPDATE (réutilise FEAT-002)
- `tr_01b_protect_immutable_documents` BEFORE UPDATE (protège 5 colonnes immuables, aucun GUC bypass)
- `tr_02_set_updated_at_documents` BEFORE UPDATE (réutilise FEAT-001)

**RPC** : `soft_delete_document(p_id uuid) RETURNS TABLE(storage_path text, hard_deleted boolean)` (public + dev) — SECURITY DEFINER, REVOKE anon. Retourne (storage_path, true) si legal_hold=false (frontend hard-delete), (NULL, false) si legal_hold=true (fichier conservé).

**RLS** : 3 policies × 2 schémas (SELECT/INSERT/UPDATE, pas de DELETE). UPDATE protégé réellement par tr_01b (seule category mutable).

**Storage** : Bucket `documents` créé (privé, MIME whitelist PDF/JPEG/PNG/WEBP, 10MB max) + 3 policies (SELECT + INSERT + DELETE — pas d'UPDATE). Path = `{env}/{landlord_id}/{document_id}.{ext}`, isolation sur segment [2].

**Tests** : `supabase/tests/rls_documents.sql` (23 tests)

---

## Résumé des changements FEAT-007 (Phase 1 — SQL)

**Nouveau type** : `public.document_type` + `dev.document_type` — ENUM (`quittance`, `recu`)

**Nouvelles tables** : `receipts` (public + dev) — Quittances et reçus PDF

**Migration** : `20260531172904_feat007_receipts.sql` (610 lignes)

**Trigger framework** :
- `tr_00_assert_receipt_lease_ownership` BEFORE INSERT (ownership lease → receipt, SECURITY DEFINER)
- `tr_01_prevent_protected_columns_change_receipts` BEFORE INSERT OR UPDATE (réutilise FEAT-002)
- `tr_03_set_receipt_stale_on_payment_archive` AFTER UPDATE OF deleted_at ON payments → marque is_stale = true sur les receipts liées

**RPC framework** : `void_receipt(p_id uuid, p_reason text)` (public + dev) — SECURITY DEFINER, REVOKE anon

**RLS** : 2 policies × 2 schémas (SELECT/INSERT seulement — pas d'UPDATE ni DELETE)

**Storage** : Bucket `receipts` créé (privé, PDF-only, 10MB max) + 2 policies (SELECT + INSERT, pas UPDATE/DELETE)

**Cohérence cross-FK** : Trigger `assert_receipt_lease_ownership()` valide lease_id → landlord_id (bail soft-deleted toléré — régularisation post-clôture)

---

## Résumé des changements FEAT-006

**Nouvelle table** : `payments` (public + dev) — Paiements mensuels d'un bail

**Migration** : `20260531102202_feat006_payments.sql` (890 lignes)

**Trigger framework** : Extend tr_00/tr_01/tr_02 à `payments` (order alphabétique maintenu)

**RPC framework** : Ajoute `soft_delete_payment()` (public + dev)

**RLS** : 3 policies × 2 schémas (SELECT/INSERT/UPDATE, pas de DELETE)

**Cohérence cross-FK** : Trigger `assert_payment_lease_ownership()` SECURITY DEFINER valide lease_id → landlord_id

---

## Résumé des changements FEAT-002

**Nouvelles tables** : `properties`, `tenants`, `leases` (public + dev)

**Colonnes ajoutées à `landlords`** : `full_name`, `phone`, `address`

**FK change** : `landlords.id → auth.users(id)` : CASCADE → NO ACTION (rétention 5 ans RGPD)

**Soft-delete** : Implémentation exhaustive (24 policies RLS pour les 4 tables × 2 schémas × SELECT/INSERT/UPDATE, aucune DELETE)

**Trigger framework** : Pattern tr_00/tr_01/tr_02 pour ordre d'exécution alphabétique stable

**RPC framework** : 4 RPC × 2 schémas pour soft-delete (+ versions dev)

**Protection colonne** : Trigger `prevent_protected_columns_change()` bloque modification de `deleted_at`, `created_at` sauf flag de session `app.allow_deleted_at_change = '1'`

**Cohérence cross-FK** : Trigger `assert_lease_ownership_consistency()` SECURITY DEFINER valide la triade (property, tenant, lease) appartient au même landlord

---

## Notes

- **Multi-env strategy** : Same database hosts `public` (PROD) et `dev` (DEV) sur Supabase free tier
- **Migration rule** : Toutes les migrations futures DOIVENT appliquer les changements aux DEUX schémas (docs/ENVIRONMENTS.md)
- **Applied to production** : FEAT-002 exécutée 2026-05-28 ~12:00 UTC; FEAT-006 en staging (prête prod)
- **RLS tests** : `supabase/tests/rls_landlords.sql` (14), `rls_properties.sql` (12), `rls_tenants.sql` (12), `rls_leases.sql` (26), `rls_payments.sql` (31), `rls_receipts.sql` (31) = 126 tests totaux
- **Date hardening** : Bornes 1900-01-01 à 2100-12-31 appliquées à leases (FEAT-005), payments (FEAT-006) et receipts (FEAT-007)
- **Applied to production** : FEAT-007 Phase 1 (SQL) exécutée 2026-05-31 via supabase db push (confirmed "Remote database is up to date")
