# Edge Functions et RPC — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/migrations/` + `supabase/functions/`. **Dernière sync** : 2026-06-01 (FEAT-008 — Edge Function send-receipt implémentée)

## Edge Functions (Deno / TypeScript)

### Fonctions déployées

**`generate-receipt`** (FEAT-007 Phase 2, active) :

| Propriété | Valeur |
|---|---|
| **Dossier** | `supabase/functions/generate-receipt/` |
| **Fichiers** | index.ts, pdf_layout.ts, types.ts, deps.ts, deno.json, tests/ |
| **Invocation** | POST `/functions/v1/generate-receipt` (JWT required) |
| **Body** | `{lease_id: uuid, schema: 'public' \| 'dev'}` |
| **Retour** | `{receipt_id: uuid, pdf_url: string}` |
| **Auth** | JWT required (authentified user = landlord_id) |
| **Secrets** | — (aucun) |
| **Dépendances** | pdf-lib@1.17.1, @supabase/supabase-js@2.45.0 |
| **Priorité** | P0 |

**Étapes** :
1. Validate lease_id ownership (auth.uid() = landlord_id via JWT)
2. Fetch payments for lease (period-grouped)
3. Build PDF with pdf-lib (FR format, loi 1989 mentions légales)
4. Upload PDF to Storage `receipts/<landlord_id>/<receipt_id>.pdf`
5. INSERT `receipts` table via RLS (landlord_id from auth.uid())
6. Return receipt_id + signed URL (5 min expiry)

**Blockers fixes** (FEAT-007 Round 2) :
- CORS allowlist : Flutter Web origin allowed
- Timeout : respects 540s limit (build + upload)
- Privacy : no sensitive data in logs

---

**`send-receipt`** (FEAT-008, implémentée — déploiement en attente des secrets Resend) :

| Propriété | Valeur |
|---|---|
| **Dossier** | `supabase/functions/send-receipt/` |
| **Fichiers** | index.ts, email_template.ts, resend_client.ts, types.ts, deps.ts, deno.json, tests/ |
| **Invocation** | POST `/functions/v1/send-receipt` (JWT required) |
| **Body** | `{receipt_id: uuid, schema: 'public' \| 'dev'}` |
| **Retour 200** | `{success: true, sent_at: ISO, sent_to_email: string, resend_id: string}` |
| **Auth** | JWT required (landlord_id = auth.uid()) |
| **Secrets** | `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `ALLOWED_ORIGINS` (optionnel) |
| **Dépendances** | @supabase/supabase-js@2.45.0, fetch natif Deno (pas de SDK Resend) |
| **Priorité** | P0 |

**Pipeline** :
1. CORS preflight check + Origin allowlist (réutilise `_shared/cors.ts`)
2. Méthode POST only
3. Parse body — valide `receipt_id` (UUID v4) + `schema` (enum strict)
4. JWT verify via `createClientWithJwt` + `auth.getUser()`
5. Charge `receipts` (avec JOIN `leases.tenants`) via RLS — `data == null` → 404
6. Valide état quittance : `is_voided` / `is_stale` → 422 `receipt_invalid` ; `pdf_path IS NULL` → 422 `pdf_unavailable`
7. Valide `tenant.email` NOT NULL / non vide → sinon 422 `tenant_no_email`
8. Charge `landlord.full_name` (signature mail)
9. Crée signed URL Storage (60s) → fetch PDF → encode base64
10. Construit email via `email_template.ts` (sujet + HTML minimal FR)
11. Envoie via `resend_client.ts` → 429 → 429 `quota_exceeded` ; autres erreurs → 500 `email_send_failed`
12. Appelle RPC `mark_receipt_as_sent` — si RPC échoue après Resend OK : log critique `[email-sent-not-persisted]` + return 200
13. Return `{success, sent_at, sent_to_email, resend_id}`

**Codes d'erreur** :

| HTTP | Code | Quand |
|---|---|---|
| 400 | `invalid_request` | body malformé, UUID invalide, schema invalide |
| 404 | `receipt_not_found` | RLS retourne null (cross-user ou inexistant) |
| 405 | `method_not_allowed` | méthode != POST |
| 422 | `tenant_no_email` | `tenant.email IS NULL` ou vide |
| 422 | `receipt_invalid` | `is_voided = true` OU `is_stale = true` |
| 422 | `pdf_unavailable` | `pdf_path IS NULL` ou fetch Storage échoue |
| 429 | `quota_exceeded` | Resend retourne 429 |
| 500 | `email_config_missing` | `RESEND_API_KEY` ou `RESEND_FROM_EMAIL` absent |
| 500 | `email_send_failed` | autre erreur Resend (5xx, timeout, 4xx hors 422/429) |
| 500 | `internal_error` | erreur DB inattendue |

**Secrets à provisionner** :
```bash
supabase secrets set RESEND_API_KEY="re_xxx" RESEND_FROM_EMAIL="EasyRent <noreply@<domaine>>"
```

**Commande de déploiement** :
```bash
supabase functions deploy send-receipt --project-ref tbgttutodbqffrvsvkoz
```

### Fonctions planifiées

_(aucune restante pour le MVP)_

### Appel côté client

Via `lib/features/receipts/application/generate_receipt_controller.dart` :

```dart
final result = await supabase.functions.invoke(
  'generate-receipt',
  body: {'lease_id': leaseId, 'schema': schema},
);
```

Retour : `{receipt_id: ..., pdf_url: ...}`

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

#### `public.mark_receipt_as_sent(p_receipt_id uuid, p_sent_to_email text)` — FEAT-008

Marque une quittance comme envoyée par email (audit trail). SECURITY DEFINER, SET search_path = public, pg_temp.

```dart
await supabase.rpc('mark_receipt_as_sent', params: {
  'p_receipt_id': receiptId,
  'p_sent_to_email': tenantEmail,
});
```

**Retour** : la row `receipts` mise à jour (`sent_at`, `sent_to_email` renseignés).

**Checks** (dans l'ordre) :
1. `p_sent_to_email` non null et longueur 3..255 → sinon ERRCODE 22023
2. `p_sent_to_email` regex `^[^@\s]+@[^@\s]+\.[^@\s]+$` → sinon ERRCODE 22023
3. WHERE ownership (`landlord_id = auth.uid()`) + `is_voided = false` + `is_stale = false` → sinon ERRCODE P0002 (pas de fuite d'info)

**Comportement** : idempotent — 2e appel écrase `sent_at` et `sent_to_email` (cas renvoi, D2=B).

**Mécanisme** : pose `SET LOCAL app.allow_sent_columns_change = '1'` pour contourner le trigger `tr_01b_protect_sent_columns_receipts`.

**Invocation** : par l'Edge Function `send-receipt` après envoi Resend confirmé. Si RPC échoue après mail parti → log critique `[email-sent-not-persisted]` côté Edge Function + return 200 quand même (évite double-mail sur retry).

#### `dev.soft_delete_landlord()`, `dev.soft_delete_property()`, `dev.soft_delete_tenant()`, `dev.soft_delete_lease()`, `dev.soft_delete_payment()`, `dev.void_receipt()`, `dev.mark_receipt_as_sent()` — FEAT-002 + FEAT-006 + FEAT-007 + FEAT-008

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

**Cas 1 (soft-delete)** : `OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL` → `UPDATE public.receipts SET is_stale = true WHERE payment_ids @> ARRAY[NEW.id]::uuid[]`.

**Cas 2 (résurrection)** : `OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL` → recompute is_stale pour chaque receipt liée : si tous les payment_ids sont actifs (aucun deleted_at IS NOT NULL parmi les autres) → `is_stale := false`, sinon `is_stale := true`.

Index GIN `idx_public_receipts_payment_ids_gin` rend l'opérateur `@>` performant.

**Fix FEAT-007 Round 2 (E5)** : Ajout du Cas 2 (résurrection) — sans lui, un payment "ressuscité" laisserait les receipts marquées stale à jamais.

**Trigger** : `tr_03_set_receipt_stale_on_payment_archive` (public.payments)

#### `dev.recompute_receipt_stale_on_payment_archive()` — FEAT-007

Mirror de `public.recompute_receipt_stale_on_payment_archive()`, opère sur dev.payments / dev.receipts.

**Trigger** : `tr_03_set_receipt_stale_on_payment_archive` (dev.payments)

#### `public.protect_sent_columns_receipts()` — FEAT-008

Trigger BEFORE UPDATE sur `public.receipts`. Bloque toute modification de `sent_at` ou `sent_to_email` sauf si le flag de session GUC `app.allow_sent_columns_change = '1'` est posé.

Ce flag est posé **exclusivement** par la RPC `mark_receipt_as_sent` (SECURITY DEFINER) via `set_config('app.allow_sent_columns_change', '1', true)` (scope transaction).

**ERRCODE** : 42501 (insufficient_privilege) si tentative directe.

**Trigger** : `tr_01b_protect_sent_columns_receipts` BEFORE UPDATE (public.receipts)

**Note dette technique** : le mécanisme GUC est cohérent avec `app.allow_deleted_at_change` (FEAT-002). Hardening P1 : migrer vers `pg_trigger_depth()` (tracké backlog). Voir `docs/SECURITY.md §Patterns sensibles`.

#### `dev.protect_sent_columns_receipts()` — FEAT-008

Mirror DEV de `public.protect_sent_columns_receipts()`.

**Trigger** : `tr_01b_protect_sent_columns_receipts` BEFORE UPDATE (dev.receipts)

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
   - `tr_01b_protect_sent_columns_receipts` (receipts uniquement — FEAT-008, GUC app.allow_sent_columns_change)
3. **`tr_02_set_updated_at_*`** (5 tables — receipts exclue : pas de updated_at) — Met à jour updated_at
   - landlords, properties, tenants, leases, payments (FEAT-006)
4. **`tr_03_set_receipt_stale_on_payment_archive`** — AFTER UPDATE OF deleted_at sur public.payments + dev.payments (FEAT-007)
   - Soft-delete payment → marque is_stale = true sur les receipts liées
   - Résurrection payment → recompute is_stale (Cas 2, FEAT-007 Round 2 E5 fix)

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
