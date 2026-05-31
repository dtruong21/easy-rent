# Edge Functions et RPC — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/migrations/`. **Dernière sync** : 2026-05-31 (FEAT-007 Phase 1 appliquée, RPC void_receipt + triggers receipts ajoutés)

## Edge Functions (Deno / TypeScript)

_(aucune fonction déployée — `supabase/functions/` n'existe pas)_

À créer lors de FEAT-007+ (envoi quittance email).

### Fonctions planifiées

| Nom | Trigger | Auth | Secrets | Priorité | Feat |
|---|---|---|---|---|---|
| `send-receipt` | Manual (on receipt create) | JWT required | `RESEND_API_KEY` | P0 | FEAT-008 |
| `generate-receipt` | Manual (on payment record) | JWT required | — | P0 | FEAT-007 — Phase 2 (Edge Function Deno, pas encore créée) |

### Structure

À créer avec :
- Deno runtime (TypeScript)
- `import_map.json` ou `deno.json` pour dépendances (Supabase Functions v2+)
- Error handling + logging via `Db.invokeFunction()` wrapper

### Appel côté client

Via `lib/core/db.dart` :

```dart
final result = await supabase.functions.invoke(
  'send-receipt',
  body: {'receipt_id': '...', 'schema': 'public'},
);
```

Passage automatique du `schema` (public ou dev) en paramètre.

---

## RPC Postgres (SECURITY DEFINER)

Créées en FEAT-002. Exposées via `supabase.rpc()` côté client.

### Soft-delete RPC (public + dev schémas)

Chacune pose `SET LOCAL app.allow_deleted_at_change = '1'` pour contourner le trigger `tr_01_prevent_protected_columns_change()`. Ownership check (`landlord_id = auth.uid()`) dans le WHERE.

#### `public.soft_delete_landlord()` — FEAT-002

Soft-delete du landlord courant (auth.uid()). Retourne void.

```dart
await supabase.rpc('soft_delete_landlord');
```

**Error** : ERRCODE P0002 si propriétaire inexistant ou déjà supprimé.

#### `public.soft_delete_property(p_id uuid)` — FEAT-002

Soft-delete property (ownership check : `landlord_id = auth.uid()`). Retourne void.

```dart
await supabase.rpc('soft_delete_property', params: {'p_id': propertyId});
```

**Error** : ERRCODE P0002 si propriété inexistante, appartenant à un autre user, ou déjà supprimée.

#### `public.soft_delete_tenant(p_id uuid)` — FEAT-002

Soft-delete tenant (ownership check). Retourne void.

```dart
await supabase.rpc('soft_delete_tenant', params: {'p_id': tenantId});
```

#### `public.soft_delete_lease(p_id uuid)` — FEAT-002

Soft-delete lease (ownership check). Retourne void.

```dart
await supabase.rpc('soft_delete_lease', params: {'p_id': leaseId});
```

#### `public.soft_delete_payment(p_id uuid)` — FEAT-006

Soft-delete payment (ownership check : `landlord_id = auth.uid()` AND deleted_at IS NULL). Retourne void.

```dart
await supabase.rpc('soft_delete_payment', params: {'p_id': paymentId});
```

**Error** : ERRCODE P0002 si paiement inexistant, appartenant à un autre user, ou déjà supprimé.

#### `public.void_receipt(p_id uuid, p_reason text)` — FEAT-007

Annule une quittance (is_voided = true, voided_at = now(), voided_reason = p_reason). SECURITY DEFINER, SET search_path = public.

```dart
await supabase.rpc('void_receipt', params: {'p_id': receiptId, 'p_reason': reason});
```

**Error** : ERRCODE 22023 si p_reason hors bornes 3-500 chars. ERRCODE P0002 si receipt inexistante, cross-user ou déjà voided.

#### `dev.soft_delete_landlord()`, `dev.soft_delete_property()`, `dev.soft_delete_tenant()`, `dev.soft_delete_lease()`, `dev.soft_delete_payment()`, `dev.void_receipt()` — FEAT-002 + FEAT-006 + FEAT-007

Mêmes signatures que les versions public, opèrent sur schéma `dev`. Utilisées uniquement en staging/dev.

---

## Trigger Functions

### Fonctions utilisées par les triggers

Créées pour être appelées par les triggers (ne s'invoquent pas directement côté client).

#### `public.prevent_protected_columns_change()` — FEAT-002

Trigger BEFORE INSERT OR UPDATE réutilisable, appliquée à 4 tables × 2 schémas (landlords, properties, tenants, leases).

**À l'INSERT** :
- Bloque `deleted_at ≠ NULL` sauf flag `app.allow_deleted_at_change = '1'` (ERRCODE 42501)
- Force `created_at := now()` et `updated_at := now()` (pragmatique — corrige les antidates)

**À l'UPDATE** :
- Bloque modification de `deleted_at` sauf flag (ERRCODE 42501)
- Bloque modification de `created_at` (immuable, ERRCODE 42501)
- Force `updated_at := OLD.updated_at` (repris par tr_02)

**Triggers attenant** :
- `tr_01_prevent_protected_columns_change_landlords` (public + dev)
- `tr_01_prevent_protected_columns_change_properties` (public + dev)
- `tr_01_prevent_protected_columns_change_tenants` (public + dev)
- `tr_01_prevent_protected_columns_change_leases` (public + dev)
- `tr_01_prevent_protected_columns_change_payments` (public + dev) — FEAT-006

#### `public.assert_lease_ownership_consistency()` — FEAT-002

Trigger BEFORE INSERT OR UPDATE sur `public.leases`, SECURITY DEFINER, SET search_path = public.

Valide 3 cas :
1. `property_id` existe dans `public.properties`
2. `tenant_id` existe dans `public.tenants`
3. `property_id.landlord_id = NEW.landlord_id` et `tenant_id.landlord_id = NEW.landlord_id`

**Trigger** : `tr_00_assert_lease_ownership` (public)

**Error** : ERRCODE 23514 (check_violation)

Bypass RLS intentionnellement (SECURITY DEFINER) pour voir toutes les lignes et valider la cohérence cross-FK indépendamment du rôle appelant.

#### `dev.assert_lease_ownership_consistency()` — FEAT-002

Mirror de `public.assert_lease_ownership_consistency()`, opère sur schéma `dev` (lit dev.properties, dev.tenants).

**Trigger** : `tr_00_assert_lease_ownership` (dev)

#### `public.assert_payment_lease_ownership()` — FEAT-006

Trigger BEFORE INSERT OR UPDATE sur `public.payments`, SECURITY DEFINER, SET search_path = public.

Valide 2 cas :
1. `lease_id` existe dans `public.leases`
2. `lease_id.landlord_id = NEW.landlord_id`

**Trigger** : `tr_00_assert_payment_lease_ownership` (public)

**Error** : ERRCODE 23514 (check_violation)

Bypass RLS intentionnellement pour voir toutes les leases et valider la cohérence cross-FK.

#### `dev.assert_payment_lease_ownership()` — FEAT-006

Mirror de `public.assert_payment_lease_ownership()`, opère sur schéma `dev` (lit dev.leases).

**Trigger** : `tr_00_assert_payment_lease_ownership` (dev)

#### `public.assert_receipt_lease_ownership()` — FEAT-007

Trigger BEFORE INSERT sur `public.receipts`, SECURITY DEFINER, SET search_path = public.

Valide 2 cas :
1. `lease_id` existe dans `public.leases` (bail soft-deleted toléré — régularisation rétroactive)
2. `lease_id.landlord_id = NEW.landlord_id`

**Trigger** : `tr_00_assert_receipt_lease_ownership` (public)

**Error** : ERRCODE 23514 (check_violation)

#### `dev.assert_receipt_lease_ownership()` — FEAT-007

Mirror de `public.assert_receipt_lease_ownership()`, opère sur schéma `dev` (lit dev.leases).

**Trigger** : `tr_00_assert_receipt_lease_ownership` (dev)

#### `public.recompute_receipt_stale_on_payment_archive()` — FEAT-007

Trigger AFTER UPDATE OF deleted_at sur `public.payments`, SECURITY DEFINER, SET search_path = public.

Quand `OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL` (soft-delete effectué) → `UPDATE public.receipts SET is_stale = true WHERE payment_ids @> ARRAY[NEW.id]::uuid[]`. Index GIN `idx_public_receipts_payment_ids_gin` rend l'opérateur `@>` performant.

**Trigger** : `tr_03_set_receipt_stale_on_payment_archive` (public.payments)

#### `dev.recompute_receipt_stale_on_payment_archive()` — FEAT-007

Mirror de `public.recompute_receipt_stale_on_payment_archive()`, opère sur dev.payments / dev.receipts.

**Trigger** : `tr_03_set_receipt_stale_on_payment_archive` (dev.payments)

#### `public.handle_new_user()` — FEAT-001

Trigger AFTER INSERT ON `auth.users`, SECURITY DEFINER, SET search_path = public.

Auto-provisioning : insère une ligne dans `public.landlords` ET `dev.landlords` à chaque signup. Idempotent (ON CONFLICT DO NOTHING).

**Trigger** : `on_auth_user_created` AFTER INSERT ON auth.users

#### `public.set_updated_at()` — FEAT-001

Trigger BEFORE UPDATE, maintient `updated_at = now()`.

**Triggers** :
- `tr_02_set_updated_at_landlords` (public + dev)
- `tr_02_set_updated_at_properties` (public + dev)
- `tr_02_set_updated_at_tenants` (public + dev)
- `tr_02_set_updated_at_leases` (public + dev)
- `tr_02_set_updated_at_payments` (public + dev) — FEAT-006

---

## Trigger order of execution

PG exécute BEFORE INSERT OR UPDATE dans l'ordre alphabétique du nom de trigger. Ordre garanti :

1. **`tr_00_assert_*_ownership`** (leases + payments + receipts) — Validation cross-FK
   - `tr_00_assert_lease_ownership` (leases)
   - `tr_00_assert_payment_lease_ownership` (payments, FEAT-006)
   - `tr_00_assert_receipt_lease_ownership` (receipts, FEAT-007 — BEFORE INSERT uniquement)
2. **`tr_01_prevent_protected_columns_change_*`** (6 tables) — Bloque deleted_at, created_at ; force updated_at
   - landlords, properties, tenants, leases, payments (FEAT-006), receipts (FEAT-007)
3. **`tr_02_set_updated_at_*`** (5 tables — receipts exclue : pas de updated_at) — Met à jour updated_at
   - landlords, properties, tenants, leases, payments (FEAT-006)
4. **`tr_03_set_receipt_stale_on_payment_archive`** — AFTER UPDATE sur public.payments + dev.payments
   - Déclenché sur soft-delete d'un payment → marque is_stale = true sur les receipts liées (FEAT-007)

---

## Cron & Scheduled functions

_(à planifier pour FEAT-008+)_

Exemples :
- Rappel paiement loyers (10e du mois)
- Nettoyage documents archived (conservation légale 5 ans)
- Synthèse mensuelle propriétaire

---

## Helper Functions (debug)

### `dev.check_schema_parity()` — FEAT-001

Compares tables between `public` (PROD) et `dev` (DEV) schemas. Retourne TABLE (public_table text, dev_table text, status text).

**Purpose** : Debug — détecter la dérive entre schémas.

### `dev.assert_rls_both_schemas(table_name text)` — FEAT-002

Assert que RLS est activée sur la table donnée dans les deux schémas (public et dev).

**Raises** : Exception si RLS non activée.

**Purpose** : Validation — called à la fin de chaque migration pour vérifier la configuration RLS.

---

## Notes

- **RPC access control** : REVOKE ALL + GRANT EXECUTE TO authenticated — principle of least privilege
- **Soft-delete flow** : Client appelle RPC soft_delete_* → RPC pose SET LOCAL flag → trigger tr_01 le voit → UPDATE succeeds
- **SET LOCAL** : Scope = transaction courante uniquement, aucun risque de fuite entre connexions
- **SECURITY DEFINER** : Bypass RLS (intentionnel pour cohérence cross-FK, auto-provisioning)
- **void_receipt flow** : Client appelle RPC void_receipt → SECURITY DEFINER contourne l'absence de policy UPDATE → UPDATE receipts SET is_voided=true ... WHERE landlord_id = auth.uid()
- **is_stale flow** : soft_delete_payment → UPDATE payments.deleted_at → AFTER trigger tr_03 → UPDATE receipts SET is_stale=true (GIN index sur payment_ids)
