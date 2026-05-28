# Edge Functions et RPC — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/migrations/`. **Dernière sync** : 2026-05-28 (FEAT-002 mergée)

## Edge Functions (Deno / TypeScript)

_(aucune fonction déployée — `supabase/functions/` n'existe pas)_

À créer lors de FEAT-007+ (envoi quittance email).

### Fonctions planifiées

| Nom | Trigger | Auth | Secrets | Priorité | Feat |
|---|---|---|---|---|---|
| `send-receipt` | Manual (on receipt create) | JWT required | `RESEND_API_KEY` | P0 | FEAT-007 |
| `generate-receipt` | Manual (on payment record) | JWT required | — | P0 | FEAT-006 |

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

#### `dev.soft_delete_landlord()`, `dev.soft_delete_property()`, `dev.soft_delete_tenant()`, `dev.soft_delete_lease()` — FEAT-002

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

---

## Trigger order of execution

PG exécute BEFORE INSERT OR UPDATE dans l'ordre alphabétique du nom de trigger. Ordre garanti :

1. **`tr_00_assert_lease_ownership`** (leases uniquement) — Validation cross-FK
2. **`tr_01_prevent_protected_columns_change_*`** (4 tables) — Bloque deleted_at, created_at ; force updated_at
3. **`tr_02_set_updated_at_*`** (4 tables) — Met à jour updated_at

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
