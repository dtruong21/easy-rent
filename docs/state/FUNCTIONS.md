# Edge Functions et RPC — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/migrations/` + `supabase/functions/`. **Dernière sync** : 2026-06-25 (FEAT-008 Web Share API pivot, Edge Function send-receipt supprimée)

## Edge Functions (Deno / TypeScript)

### Fonctions déployées (2)

#### `generate-receipt` (FEAT-007 Phase 2 — active)

| Propriété | Valeur |
|---|---|
| Dossier | `supabase/functions/generate-receipt/` |
| Fichiers | index.ts, pdf_layout.ts, types.ts, deps.ts, deno.json, tests/ |
| Invocation | POST `/functions/v1/generate-receipt` (JWT required) |
| Body | `{lease_id: uuid, schema: 'public' \| 'dev'}` |
| Retour | `{receipt_id: uuid, pdf_url: string}` |
| Auth | JWT required (authentified user = landlord_id) |
| Secrets | _(none)_ |
| Dépendances | pdf-lib@1.17.1, @supabase/supabase-js@2.45.0 |
| Priorité | P0 (actif prod) |

**Logique** :
1. Validate lease_id ownership via JWT (auth.uid() = landlord_id)
2. Fetch payments for lease (period-grouped, RLS-filtered)
3. Build PDF with pdf-lib (FR format, loi 1989 legal mentions)
4. Upload PDF to Storage `receipts/<landlord_id>/<receipt_id>.pdf`
5. INSERT `receipts` table via RLS (landlord_id from auth.uid())
6. Return receipt_id + signed URL (5 min expiry)

**Appel côté client** :
```dart
final result = await supabase.functions.invoke(
  'generate-receipt',
  body: {'lease_id': leaseId, 'schema': schema},
);
// Retour : {receipt_id: ..., pdf_url: ...}
```

**Fichier client** : `lib/features/receipts/application/generate_receipt_controller.dart`

---

#### `_shared` (Deno utilities — support)

| Propriété | Valeur |
|---|---|
| Dossier | `supabase/functions/_shared/` |
| Fichiers | utils.ts, types.ts, constants.ts |
| Usage | Imported by `generate-receipt` |
| Purpose | Shared types, PDF layouts, constants |
| Secrets | _(none)_ |

**Contenu** :
- PDF layout helpers (header, footer, table cells)
- Constants (FR legal notices, tax ref)
- Types (LeasePayment, ReceiptData)
- Utility functions (date formatting, amount conversion)

---

### Fonctions supprimées (FEAT-008 pivot)

#### `send-receipt` (FEAT-008 Phase 1 — SUPPRIMÉE 2026-06-22)

**Raison suppression** : Pivot Web Share API native (zéro dépendance backend email, zéro secret Resend, meilleure UX native)

**Ancienne fonction** :
- Utilisait Resend SDK (email via backend)
- Nécessitait secret `RESEND_API_KEY`
- Edge Function déployée Deno TS

**Remplacement** :
- Service Flutter `web_share_service.dart` (JS interop `navigator.share()`)
- Fallback `mailto://` si Web Share API non supportée
- RPC `mark_receipt_as_sent()` appelée APRÈS succès du partage (audit trail)
- Zéro backend email, zéro dépendance API externe

---

## RPC Postgres (SECURITY DEFINER)

Créées en FEAT-002+. Exposées via `supabase.rpc()` côté client Dart.

### Soft-delete RPC (public + dev schémas)

Chacune pose `SET LOCAL app.allow_deleted_at_change = '1'` pour contourner le trigger `tr_01_prevent_protected_columns_change()`. Ownership check (`landlord_id = auth.uid()`) dans le WHERE. Idempotent.

#### `public.soft_delete_landlord()` — FEAT-002

Soft-delete du landlord courant (auth.uid()). Retourne void.

```dart
await supabase.rpc('soft_delete_landlord');
```

**Error** : ERRCODE P0002 si propriétaire inexistant ou déjà supprimé.

---

#### `public.soft_delete_property(p_id uuid)` — FEAT-002

Soft-delete property (ownership check : `landlord_id = auth.uid()`). Retourne void.

```dart
await supabase.rpc('soft_delete_property', params: {'p_id': propertyId});
```

**Error** : ERRCODE P0002 si propriété inexistante, appartenant à un autre user, ou déjà supprimée.

---

#### `public.soft_delete_tenant(p_id uuid)` — FEAT-002

Soft-delete tenant (ownership check). Retourne void.

```dart
await supabase.rpc('soft_delete_tenant', params: {'p_id': tenantId});
```

**Error** : ERRCODE P0002 si locataire inexistant ou déjà supprimé.

---

#### `public.soft_delete_lease(p_id uuid)` — FEAT-002

Soft-delete lease (ownership check). Retourne void.

```dart
await supabase.rpc('soft_delete_lease', params: {'p_id': leaseId});
```

**Error** : ERRCODE P0002 si bail inexistant ou déjà supprimé.

---

#### `public.soft_delete_payment(p_id uuid)` — FEAT-006

Soft-delete payment (ownership check : `landlord_id = auth.uid() AND deleted_at IS NULL`). Retourne void.

```dart
await supabase.rpc('soft_delete_payment', params: {'p_id': paymentId});
```

**Error** : ERRCODE P0002 si paiement inexistant, appartenant à un autre user, ou déjà supprimé.

---

#### `public.soft_delete_document(p_id uuid)` — FEAT-009

Soft-delete document (ownership check). Retourne TABLE `(storage_path text, hard_deleted boolean)`.

```dart
final result = await supabase.rpc('soft_delete_document', params: {'p_id': documentId});
// result = [{'storage_path': '...', 'hard_deleted': true/false}]
```

**Logic** :
- Si `legal_hold = false` → hard_deleted = true (frontend peut hard-delete depuis Storage)
- Si `legal_hold = true` → hard_deleted = false (fichier conservé pour audit legal)

**Error** : ERRCODE P0002 si document inexistant ou déjà supprimé.

---

### Receipt-specific RPC

#### `public.void_receipt(p_id uuid, p_reason text)` — FEAT-007

Annulation quittance (void). Ownership check (landlord_id = auth.uid()). Retourne void.

```dart
await supabase.rpc('void_receipt', params: {
  'p_id': receiptId,
  'p_reason': 'Erreur date loyer',
});
```

**Validation** :
- `p_reason` : char_length BETWEEN 3 AND 500
- `is_voided = false` actuellement (ne peut pas annuler deux fois)

**Error** : ERRCODE P0002 si quittance inexistante, ERRCODE 23514 (check_violation) si reason invalide.

---

#### `public.mark_receipt_as_sent(p_receipt_id uuid, p_sent_to_email text)` — FEAT-008

Marquer quittance comme partagée (audit trail post-Web Share API). SECURITY DEFINER. Ownership check + validation email. Retourne TABLE `receipts`.

```dart
final result = await supabase.rpc('mark_receipt_as_sent', params: {
  'p_receipt_id': receiptId,
  'p_sent_to_email': tenantEmail,
});
```

**Validation** :
- Ownership : `landlord_id = auth.uid()`
- `is_voided = false` (ne peut pas envoyer quittance annulée)
- `is_stale = false` (ne peut pas envoyer si paiement archivé)
- `p_sent_to_email` : regex email valide + char_length BETWEEN 3 AND 255

**Idempotence** : 2e appel écrase `sent_at` + `sent_to_email` (dernière tentative enregistrée)

**Error** :
- ERRCODE P0002 si quittance inexistante, voided, ou stale
- ERRCODE 22023 si email invalide
- ERRCODE 23514 si quittance appartient à un autre landlord

---

#### `public.soft_delete_lease()` avec trigger cascade

**Trigger** : `tr_03_set_receipt_stale_on_payment_archive` (AFTER UPDATE OF deleted_at ON payments)

Lorsqu'un paiement est archivé (soft-deleted), marque `is_stale = true` sur toutes les receipts qui référencent ce paiement via `payment_ids[]` (GIN index).

```sql
UPDATE receipts
SET is_stale = true
WHERE lease_id = (SELECT lease_id FROM payments WHERE id = NEW.id)
  AND payment_ids @> ARRAY[NEW.id];
```

---

## Version dev (schéma dev)

Toutes les RPC ci-dessus existent en version `dev.*` (préfixe `dev.`), opérant sur le schéma `dev` :
- `dev.soft_delete_landlord()`
- `dev.soft_delete_property(p_id uuid)`
- `dev.soft_delete_tenant(p_id uuid)`
- `dev.soft_delete_lease(p_id uuid)`
- `dev.soft_delete_payment(p_id uuid)`
- `dev.soft_delete_document(p_id uuid)`
- `dev.void_receipt(p_id uuid, p_reason text)`
- `dev.mark_receipt_as_sent(p_receipt_id uuid, p_sent_to_email text)`

Signatures exactes, mais opèrent sur `dev.landlords`, `dev.properties`, etc.

---

## Appels côté client Dart

Pattern Riverpod + supabase_flutter :

```dart
// Via provider
final supabase = ref.read(supabaseProvider);

// RPC call
await supabase.rpc('soft_delete_property', params: {'p_id': id});

// Edge Function call
final result = await supabase.functions.invoke(
  'generate-receipt',
  body: {'lease_id': leaseId, 'schema': schema},
);
```

---

## Notes

- **Multi-env** : Toutes les RPC existent sur public (PROD) et dev (DEV)
- **Ownership** : Tous les checks sont côté DB (RLS + WHERE clause)
- **Idempotence** : Soft-delete RPC sont idempotentes (2e appel = no-op, error P0002)
- **Audit trail** : sent_at, voided_at, deleted_at conservent l'historique complet
- **Edge Function timeout** : Respect 540s limit pour generate-receipt (build + upload PDF)
