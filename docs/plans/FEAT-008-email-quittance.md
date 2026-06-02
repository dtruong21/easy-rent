# Plan — [FEAT-008] Envoyer une quittance par email (Resend)

> Source story : [`docs/backlog/008-email-quittance.md`](../backlog/008-email-quittance.md)
> Pattern de référence : [`docs/plans/FEAT-007-quittance-pdf.md`](FEAT-007-quittance-pdf.md)
> Décisions produit actées : **D1=A** (bloquer si tenant sans email) · **D2=B** (renvoi avec confirmation) · **D3=B** (pas de reply-to) · **D4=B** (HTML minimal) · **D5=A** (429 explicite, pas de queue)

## 1. Vue d'ensemble

**Objectif** : depuis la liste des quittances d'un bail, permettre au bailleur d'envoyer en un clic le PDF d'une quittance valide au locataire via Resend, avec persistance d'un audit trail (`sent_at`, `sent_to_email`). Le PDF est joint en base64 (pas de lien public exposable).

**Dépendances** :
- FEAT-007 (table `receipts` + bucket Storage `receipts/` + UI `LeaseReceiptsPage` + `ReceiptListTile` + pattern Edge Function `_shared/`)
- `tenants.email` (FEAT-004 — déjà présent, format validé regex)
- `landlords.full_name` (FEAT-007 — déjà obligatoire pour générer une quittance ; on s'appuie sur cet invariant pour signer le mail)

**Débloque** : aucune feature aval directe — point final du flow quittance MVP.

**Scope** :
- Migration SQL : 2 colonnes (`sent_at`, `sent_to_email`) sur `public.receipts` + `dev.receipts` + protection trigger
- RPC `mark_receipt_as_sent(p_receipt_id uuid, p_sent_to_email text)` SECURITY DEFINER
- Edge Function Deno `send-receipt` (réutilise `_shared/cors.ts`, `_shared/supabase_client.ts`)
- Extension Flutter `lib/features/receipts/` : controller + repository + bouton + dialog de confirmation
- Extension `mapEdgeFunctionError` pour les nouveaux codes (`tenant_no_email`, `receipt_invalid`, `quota_exceeded`, `pdf_unavailable`)
- Tests Deno (6 fichiers) + tests SQL RLS (1 fichier) + tests Flutter (5 fichiers)

**Hors scope** :
- Envoi groupé / cron — P1
- Webhook Resend `email.delivered` / `email.bounced` — P2
- Queue (`email_queue` table) — P1
- Configuration reply-to opt-in bailleur — P1
- Notification push / SMS — P2
- Re-génération PDF si absent — laisser remonter l'erreur 422 explicite

---

## 2. Modèle de données — extension `receipts`

### 2.1 Colonnes ajoutées

| Colonne | Type | Contraintes |
|---|---|---|
| `sent_at` | `timestamptz` | NULL = jamais envoyé. Pas de DEFAULT. |
| `sent_to_email` | `text` | NULL si `sent_at IS NULL`. Sinon NOT NULL. CHECK `char_length BETWEEN 3 AND 255`. |

**Contraintes** (ajoutées à `receipts_voiding_consistency` style) :

```sql
ALTER TABLE public.receipts
  ADD COLUMN sent_at      timestamptz NULL,
  ADD COLUMN sent_to_email text       NULL;

ALTER TABLE public.receipts
  ADD CONSTRAINT receipts_sent_consistency
  CHECK (
    (sent_at IS NULL  AND sent_to_email IS NULL) OR
    (sent_at IS NOT NULL AND sent_to_email IS NOT NULL
       AND char_length(sent_to_email) BETWEEN 3 AND 255)
  );
```
Miroir sur `dev.receipts`.

**Pas d'index** : faible cardinalité (la requête "liste quittances d'un bail" est déjà servie par `idx_*_receipts_lease_id`), pas de query plan justifiant un index `sent_at IS NULL` (filtre rarement matérialisé côté API, presque toujours servi via récup intégrale du bail).

**Pas de policy UPDATE** : la table reste sans policy UPDATE. La mise à jour passe **exclusivement** par la RPC `mark_receipt_as_sent` (cf. §2.3).

### 2.2 Protection trigger — extension de `tr_01_prevent_protected_columns_change_receipts`

Risque : si un jour une policy UPDATE était ajoutée par mégarde, n'importe quel client pourrait mentir sur `sent_at`. Mitigation : étendre la fonction existante `public.prevent_protected_columns_change()` ? **Non** — cette fonction est utilisée par 6 tables, on ne la pollue pas avec une logique spécifique à receipts.

**Décision** : ajouter un nouveau trigger dédié `tr_01b_protect_sent_columns_receipts` BEFORE UPDATE ON `receipts` qui bloque toute modification de `sent_at` ou `sent_to_email` sauf si la variable de session `app.allow_sent_columns_change = '1'` est posée (pattern strictement identique à `app.allow_deleted_at_change`). La RPC `mark_receipt_as_sent` est la seule autorisée à poser ce flag.

```sql
CREATE OR REPLACE FUNCTION public.protect_sent_columns_receipts()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  allow_flag text := current_setting('app.allow_sent_columns_change', true);
BEGIN
  IF allow_flag IS DISTINCT FROM '1' THEN
    IF NEW.sent_at IS DISTINCT FROM OLD.sent_at THEN
      RAISE EXCEPTION 'sent_at is protected — use mark_receipt_as_sent RPC'
        USING ERRCODE = '42501';
    END IF;
    IF NEW.sent_to_email IS DISTINCT FROM OLD.sent_to_email THEN
      RAISE EXCEPTION 'sent_to_email is protected — use mark_receipt_as_sent RPC'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
```
Miroir `dev.protect_sent_columns_receipts()`. Triggers attachés aux deux schémas.

### 2.3 RPC `mark_receipt_as_sent(p_receipt_id uuid, p_sent_to_email text)`

Pattern strictement aligné `void_receipt` (FEAT-007).

```sql
CREATE OR REPLACE FUNCTION public.mark_receipt_as_sent(
  p_receipt_id uuid,
  p_sent_to_email text
)
RETURNS public.receipts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.receipts;
BEGIN
  IF p_sent_to_email IS NULL OR char_length(p_sent_to_email) NOT BETWEEN 3 AND 255 THEN
    RAISE EXCEPTION 'sent_to_email must be 3..255 chars' USING ERRCODE = '22023';
  END IF;
  -- Format basique (idem regex côté tenants.email).
  IF p_sent_to_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'sent_to_email format invalid' USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('app.allow_sent_columns_change', '1', true); -- scope = transaction

  UPDATE public.receipts
     SET sent_at = now(),
         sent_to_email = p_sent_to_email
   WHERE id = p_receipt_id
     AND landlord_id = auth.uid()
     AND is_voided = false
     AND is_stale  = false
  RETURNING * INTO result;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'receipt not found, voided, stale, or not owned'
      USING ERRCODE = 'P0002';
  END IF;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_receipt_as_sent(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_receipt_as_sent(uuid, text) TO authenticated;
```
Miroir `dev.mark_receipt_as_sent(uuid, text)`.

**Pourquoi RPC SECURITY DEFINER plutôt qu'UPDATE direct ?**
1. Aucune policy UPDATE n'existe sur `receipts` (immutabilité document) — on ne veut pas ouvrir un trou par "policy UPDATE conditionnelle"
2. La RPC fait l'ownership check + le check void/stale dans la même transaction, atomique
3. La RPC est le seul chemin pouvant poser `app.allow_sent_columns_change = '1'` — garantit que les colonnes ne sont pas réécrites par erreur ailleurs
4. Cohérent avec `void_receipt`, `soft_delete_*` (pattern unique dans le projet)

### 2.4 Vérification fin de migration

`SELECT dev.assert_rls_both_schemas('receipts');` (déjà appelée en FEAT-007, on la rappelle pour idempotence).

---

## 3. Edge Function `send-receipt`

### 3.1 Localisation et structure

```
supabase/functions/
├── _shared/                       # Existant — réutilisé tel quel
│   ├── cors.ts
│   ├── supabase_client.ts
│   └── money_format.ts
└── send-receipt/                  # NOUVEAU
    ├── index.ts                   # Handler Deno.serve
    ├── deps.ts                    # imports (idem generate-receipt)
    ├── email_template.ts          # Construction du sujet + corps HTML minimal FR
    ├── resend_client.ts           # Wrapper fetch POST Resend /emails + mapping erreurs
    ├── types.ts                   # SendReceiptRequest, SuccessResponse, ErrorResponse
    ├── deno.json                  # imports map identique à generate-receipt
    └── tests/
        ├── input_validation_test.ts
        ├── tenant_no_email_test.ts
        ├── receipt_invalid_test.ts        # void / stale / pdf absent
        ├── cross_user_404_test.ts
        ├── resend_quota_429_test.ts
        └── email_template_test.ts         # sujet + corps + caractères FR
```

**Pas de nouvelle dépendance `_shared/`** — toute la logique métier (template HTML, wrapper Resend) reste locale à `send-receipt/`.

### 3.2 Dépendances Deno

| Import | Source | Usage |
|---|---|---|
| `@supabase/supabase-js@2.45.0` | `https://esm.sh/...` | Identique generate-receipt (réutilise `createClientWithJwt`) |
| `fetch` natif Deno | — | Appel HTTP Resend API (pas de SDK) |

**Pas de SDK Resend** : l'API REST `POST /emails` est simple, un wrapper de 30 lignes (`resend_client.ts`) suffit. Évite un import esm.sh supplémentaire et un cold-start plus lourd.

### 3.3 Secret `RESEND_API_KEY`

Provisionné via :
```bash
supabase secrets set RESEND_API_KEY="re_xxxxxxxxxxxxxxxxx"
# (à faire pour staging ET prod — deux clés distinctes recommandées si plans Resend différents)
```

**Garde-fou** : jamais bundlé côté client. La clé n'est lue qu'au runtime via `Deno.env.get('RESEND_API_KEY')` dans `resend_client.ts`. Si absente → 500 "Configuration email manquante" (et log explicite côté serveur).

**Domaine vérifié Resend** : prérequis infra (cf. story §Dépendances). Le `from` du mail doit être un domaine vérifié dans le compte Resend. Décision MVP : `from = "EasyRent <noreply@<domaine_verifie>>"` — domaine exact à figer dans une variable d'env `RESEND_FROM_EMAIL` (secret Edge Function) pour éviter de hard-coder.

```bash
supabase secrets set RESEND_FROM_EMAIL="EasyRent <noreply@easyrent.app>"
```

### 3.4 Contrat HTTP

**POST `/functions/v1/send-receipt`**

Headers :
- `Authorization: Bearer <JWT>` (obligatoire — `verify_jwt = true`)
- `Content-Type: application/json`

Body :
```json
{ "receipt_id": "<uuid>", "schema": "public" | "dev" }
```

Response 200 :
```json
{
  "success": true,
  "sent_at": "2026-06-01T14:32:10.123Z",
  "sent_to_email": "locataire@example.com",
  "resend_id": "<resend-message-id>"
}
```

Codes d'erreur (tous au format `{ "error": "<code>", "message"?: "<msg humain>" }`) :

| HTTP | `error` code | Quand | Mapping UI |
|---|---|---|---|
| 400 | `invalid_request` | body malformé, `receipt_id` non UUID, schema invalide | "Requête invalide. Réessayez." |
| 401 | (Supabase intercepte) | JWT absent/invalide | "Session expirée." |
| 403 | (CORS allowlist) | Origin non autorisée | (jamais affichée — bloquée avant) |
| 404 | `receipt_not_found` | RLS retourne 0 ligne (cross-user OU inexistant — pas de distinction par sécurité) | "Quittance introuvable." |
| 405 | `method_not_allowed` | méthode != POST | (jamais affichée) |
| 422 | `tenant_no_email` | `tenant.email IS NULL OR ''` | "Impossible d'envoyer : le locataire n'a pas d'adresse email. Mettez à jour sa fiche." |
| 422 | `receipt_invalid` | `is_voided = true` OR `is_stale = true` | "Quittance annulée ou périmée — impossible à envoyer." |
| 422 | `pdf_unavailable` | `pdf_path IS NULL` OR signed URL fetch fails | "PDF indisponible pour cette quittance. Régénérez-la." |
| 429 | `quota_exceeded` | Resend retourne 429 | "Quota d'envoi dépassé. Réessayez le mois prochain." |
| 500 | `email_send_failed` | autre erreur Resend (5xx, timeout, body invalide) | "Échec de l'envoi de l'email. Réessayez plus tard." |
| 500 | `internal_error` | erreur DB / Storage inattendue | "Une erreur est survenue. Réessayez." |

### 3.5 Pipeline d'exécution

1. **CORS check** : `handleCors(req)` (idem generate-receipt — réutilisé tel quel).
2. **Méthode** : POST only, sinon 405.
3. **Parse body** : `receipt_id` (UUID v4) + `schema` (public|dev) via `parseSchema`. Erreurs → 400.
4. **Auth** : `createClientWithJwt(req)` + `auth.getUser()`. Pas de user → 401.
5. **Load receipt + lease + tenant** en une seule requête avec join Supabase :
   ```ts
   const { data, error } = await supabase
     .schema(schemaName)
     .from('receipts')
     .select('id, landlord_id, lease_id, pdf_path, is_voided, is_stale, period_start, period_end, total_cents, document_type, leases(tenant_id, tenants(first_name, last_name, email))')
     .eq('id', receipt_id)
     .maybeSingle();
   ```
   RLS filtre par `landlord_id = auth.uid()`. `data == null` → 404 `receipt_not_found`.
6. **Validation receipt** :
   - `is_voided` → 422 `receipt_invalid`
   - `is_stale` → 422 `receipt_invalid`
   - `pdf_path IS NULL OR ''` → 422 `pdf_unavailable`
7. **Validation tenant** :
   - `data.leases.tenants.email IS NULL OR trim() == ''` → 422 `tenant_no_email`
8. **Charger landlord.full_name** (pour le corps du mail — signataire) :
   ```ts
   const { data: landlord } = await supabase
     .schema(schemaName)
     .from('landlords')
     .select('full_name')
     .eq('id', userId)
     .maybeSingle();
   ```
   Si NULL → 500 `internal_error` (cas anormal — landlord est censé avoir full_name puisqu'il a réussi à générer la quittance ; mais on garde le check défensif).
9. **Récupérer PDF** :
   ```ts
   const { data: signed } = await supabase.storage.from('receipts')
     .createSignedUrl(receipt.pdf_path, 60); // 60s suffit
   const pdfBytes = new Uint8Array(await (await fetch(signed.signedUrl)).arrayBuffer());
   const pdfBase64 = base64Encode(pdfBytes);
   ```
   Échec → 422 `pdf_unavailable`.
10. **Construire email** via `email_template.ts` :
    - `subject = "Votre quittance de loyer — <mois en français> <année>"` (ex: "Votre quittance de loyer — mai 2026", extrait de `receipt.period_start`)
    - `html` minimal : `<p>` salutation tenant, `<p>` corps "Bonjour <prénom>, vous trouverez en pièce jointe votre quittance de loyer pour la période du JJ/MM/YYYY au JJ/MM/YYYY pour un montant de X,XX €.", `<p>` signataire `<landlord.full_name>`, `<p>` mention légale courte (loi 1989 art. 21 — "Cette quittance vous libère du paiement pour la période concernée."). Pas de logo, pas de CSS lourd, fond blanc. Caractères UTF-8 (é, è, ç, €) testés.
    - `attachments = [{ filename: "quittance_<periodMonth>_<periodYear>.pdf", content: pdfBase64 }]`
11. **Appel Resend** via `resend_client.ts` :
    ```ts
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: RESEND_FROM_EMAIL,
        to: [tenant.email],
        subject,
        html,
        attachments,
      }),
    });
    ```
    Mapping erreurs :
    - 200 → success, parse `{ id }` comme `resend_id`
    - 429 → return 429 `quota_exceeded`
    - 422 (validation Resend, ex: invalid email format) → return 422 `tenant_no_email` avec log explicite (cas rare — l'email a passé la regex Postgres mais Resend le refuse)
    - 401/403 Resend → return 500 `email_send_failed` + log critique (API key révoquée ou domaine non vérifié)
    - 5xx Resend → return 500 `email_send_failed`
    - timeout/network → return 500 `email_send_failed`
12. **Si Resend OK → call RPC `mark_receipt_as_sent`** :
    ```ts
    const { data: updated, error: rpcErr } = await supabase
      .schema(schemaName)
      .rpc('mark_receipt_as_sent', {
        p_receipt_id: receipt.id,
        p_sent_to_email: tenant.email,
      });
    ```
    Échec RPC après email envoyé → log `[email-sent-not-persisted] receipt=<id>` critique mais return 200 quand même (l'email EST parti — l'utilisateur n'a pas à le savoir). Le ré-envoi futur sera autorisé sans confirmation, c'est un dégât acceptable face au double-mensonge "email parti / on dit non".
    
    **Alternative considérée et rejetée** : retourner 500 si RPC échoue. Rejeté parce que ça induit le bailleur à retry → double email réel envoyé.
13. **Return 200** `{ success, sent_at, sent_to_email, resend_id }`.

### 3.6 Ordre commit/email (partial-failure)

Le seul scénario de divergence est "email parti mais RPC échoue" (étape 12). Géré au §3.5 étape 12. Aucun autre point ne peut avoir d'effet de bord externe.

### 3.7 Logs (sans fuite de PII)

- `[send-receipt] start landlord=<id> receipt=<id>` (UUIDs seulement)
- `[send-receipt] success landlord=<id> receipt=<id> resend_id=<id>`
- `[send-receipt] resend_429 landlord=<id> receipt=<id>` (pour monitoring quota)
- `[email-sent-not-persisted] receipt=<id>` (alerte critique)
- **Jamais loguer** : `tenant.email`, `landlord.full_name`, contenu HTML, base64 PDF. L'audit est dans la DB (`sent_to_email`).

---

## 4. Structure Flutter — extension `lib/features/receipts/`

### 4.1 Fichiers nouveaux

```
lib/features/receipts/
├── domain/
│   ├── send_receipt_state.dart            # NOUVEAU — sealed union freezed
│   └── send_receipt_state.freezed.dart    # GÉNÉRÉ
├── application/
│   └── send_receipt_controller.dart       # NOUVEAU — StateNotifier autoDispose
└── presentation/
    └── widgets/
        ├── send_receipt_button.dart       # NOUVEAU — IconButton + dialog confirmation
        └── confirm_resend_dialog.dart     # NOUVEAU — AlertDialog "déjà envoyé le ..."
```

### 4.2 Fichiers modifiés

- `lib/features/receipts/domain/receipt.dart` : ajouter `sentAt` (`DateTime?`) + `sentToEmail` (`String?`) au modèle freezed (avec `@JsonKey(name: 'sent_at' / 'sent_to_email')`). Re-générer `.freezed.dart` et `.g.dart` via `build_runner`. Ajouter extension getters :
  - `bool get hasBeenSent => sentAt != null`
  - `String? get sentAtLabel` (ex: "01/06/2026") via `FrenchDate.format`
  - `String? get maskedSentToEmail` — masquage RGPD : `"j***@example.com"` (premier char + 3 étoiles + `@domaine`)
- `lib/features/receipts/data/receipts_repository.dart` : ajouter méthode `Future<SendReceiptResult> sendReceipt({required String receiptId})`. L'invocation Edge Function passe par `Db.invokeFunction('send-receipt', body: {'receipt_id': receiptId})` (le helper injecte le schema actif). Lance les exceptions typées (`TenantNoEmailException`, `ReceiptInvalidException`, `PdfUnavailableException`, `EmailQuotaExceededException`).
- `lib/core/utils/edge_function_error_mapper.dart` : étendre pour mapper :
  - `tenant_no_email` → lever `TenantNoEmailException` (nouvelle classe)
  - `receipt_invalid` → lever `ReceiptInvalidException` (nouvelle classe)
  - `pdf_unavailable` → lever `PdfUnavailableException`
  - `quota_exceeded` (status 429) → lever `EmailQuotaExceededException`
  - `email_send_failed` (status 500) → message "Échec de l'envoi de l'email. Réessayez plus tard."
- `lib/features/receipts/presentation/widgets/receipt_list_tile.dart` : insérer `SendReceiptButton(receipt: receipt, leaseId: leaseId)` dans le `Row` du `trailing`, juste avant le bouton "télécharger". Visible uniquement si **non voided ET non stale** (sinon disabled visuel — pas de message d'erreur silencieux).

### 4.3 États du `send_receipt_state.dart` (sealed freezed)

```dart
@freezed
sealed class SendReceiptState with _$SendReceiptState {
  const factory SendReceiptState.idle() = SendReceiptIdle;
  const factory SendReceiptState.submitting() = SendReceiptSubmitting;
  const factory SendReceiptState.confirmingResend({
    required DateTime previousSentAt,
    required String previousMaskedEmail,
  }) = SendReceiptConfirmingResend;
  const factory SendReceiptState.success({
    required DateTime sentAt,
    required String sentToEmail,
  }) = SendReceiptSuccess;
  const factory SendReceiptState.error({required String message}) = SendReceiptError;
  const factory SendReceiptState.tenantNoEmail() = SendReceiptTenantNoEmail;
  const factory SendReceiptState.rateLimited() = SendReceiptRateLimited;
}
```

### 4.4 Logique du `send_receipt_controller.dart`

API publique :
- `Future<void> initiate({required Receipt receipt, required String leaseId})` :
  - Si `receipt.hasBeenSent` → state = `confirmingResend(prev...)` (le widget ouvrira le dialog)
  - Sinon → appel direct `_send(receipt, leaseId)`
- `Future<void> confirmResend({required Receipt receipt, required String leaseId})` :
  - Appelle `_send(receipt, leaseId)` (passe outre la confirmation)
- `void reset()` : revient à `idle`
- `_send` privée :
  - state = `submitting`
  - try : `repo.sendReceipt(receiptId: receipt.id)` → state = `success(...)` + `ref.invalidate(leaseReceiptsProvider(leaseId))`
  - catch `TenantNoEmailException` → state = `tenantNoEmail`
  - catch `EmailQuotaExceededException` → state = `rateLimited`
  - catch `ReceiptInvalidException` → state = `error("Quittance annulée ou périmée — impossible à envoyer.")`
  - catch `PdfUnavailableException` → state = `error("PDF indisponible — régénérez la quittance.")`
  - catch `FunctionException` → `mapEdgeFunctionError(e)` → state = `error(msg)`
  - catch tout autre → state = `error("Une erreur est survenue. Réessayez.")`

Provider :
```dart
final sendReceiptControllerProvider =
    StateNotifierProvider.autoDispose<SendReceiptController, SendReceiptState>(
  (ref) => SendReceiptController(ref),
);
```

### 4.5 Widget `send_receipt_button.dart`

Comportement :
- Si `receipt.isVoided || receipt.isStale` → `IconButton` désactivé visuellement (couleur grise, tooltip "Quittance invalide — envoi impossible"). Pas de tap handler.
- Sinon :
  - Icon = `Icons.mail_outline` si `!receipt.hasBeenSent`, `Icons.mark_email_read_outlined` (avec couleur primaryContainer) si `receipt.hasBeenSent`
  - Tooltip = "Envoyer par email" / "Renvoyer (envoyé le JJ/MM/YYYY)"
  - `onPressed = () => ref.read(sendReceiptControllerProvider.notifier).initiate(receipt: receipt, leaseId: leaseId)`
- Listener `ref.listen<SendReceiptState>` :
  - `confirmingResend` → `showDialog(ConfirmResendDialog(...))` → si confirme appelle `confirmResend`
  - `submitting` → affichage `CircularProgressIndicator` (taille 16) à la place de l'icône (sans bloquer le bouton lui-même — désactivation visuelle)
  - `success` → `SnackBar("Quittance envoyée à ${maskedSentToEmail}")` + `controller.reset()`
  - `tenantNoEmail` → `SnackBar("Ajoutez l'adresse email du locataire dans sa fiche pour activer l'envoi.")` + bouton "Modifier" action → navigation vers tenant edit (si lien dispo, sinon juste le message). + `reset()`
  - `rateLimited` → `SnackBar("Quota d'envoi dépassé. Réessayez le mois prochain.")` (durée 6s, color errorContainer) + `reset()`
  - `error` → `SnackBar(message)` + `reset()`

### 4.6 Widget `confirm_resend_dialog.dart`

`AlertDialog` :
- Title : "Renvoyer cette quittance ?"
- Content : `Text("Vous l'avez déjà envoyée le ${previousSentAt formaté} à ${previousMaskedEmail}.\n\nVoulez-vous l'envoyer à nouveau ?")`
- Actions : `TextButton("Annuler")` (pop sans confirmer) + `FilledButton("Renvoyer", onPressed: () { pop; onConfirm(); })`

### 4.7 Helpers réutilisés

| Helper | Status |
|---|---|
| `FrenchDate.format` | Réutiliser ([`lib/core/utils/french_date.dart`](../../lib/core/utils/french_date.dart)) |
| `MoneyFormat.formatEurosFromCents` | Réutiliser |
| `mapEdgeFunctionError` | À ÉTENDRE (cf. §4.2) |
| `Db.invokeFunction` | Réutiliser (injection schema auto) |

### 4.8 Routes go_router

**Aucune nouvelle route**. Le bouton est purement contextuel (intégré dans `ReceiptListTile`).

---

## 5. Décisions techniques

| Sujet | Décision |
|---|---|
| RPC SECURITY DEFINER vs UPDATE direct | RPC. Évite d'ajouter une policy UPDATE conditionnelle sur `receipts` qui risquerait d'être trop permissive. Pattern unique aligné `void_receipt`. |
| Trigger protect dédié vs extension `prevent_protected_columns_change` | Trigger dédié `tr_01b_protect_sent_columns_receipts`. Ne pollue pas la fonction partagée par 6 tables. |
| PDF en attachment base64 vs lien public | **Attachment base64**. (a) Privacy : pas d'URL exposable interceptable, (b) Fiabilité : 100% des clients mail affichent la PJ vs 60-80% pour les liens téléchargés (corporate proxies, archivage). Coût : +33% taille body Resend (PDF ~1MB → ~1.3MB en base64, sous la limite Resend 40MB). |
| Pas de webhook Resend MVP | Pas de webhook `email.delivered` / `email.bounced` : (a) complexité (endpoint public + signature HMAC), (b) données opérationnelles non critiques pour MVP, (c) la mention `sent_at` est suffisante audit. P2. |
| Pas de notification push | Hors scope. P2. |
| Pas de queue rate-limit | D5 acté : 429 explicite. Resend free tier = 3 000/mois (~100 bailleurs × 30 quittances). Queue = P1. |
| Pas de reply-to | D3 acté. Le mail provient de `noreply@<domaine_verifie>`. Le locataire ne peut pas répondre au bailleur. |
| HTML minimal | D4 acté. Pas de logo, pas de CSS. Texte FR clair, mention loi 1989 art. 21. |
| Bloquer si tenant sans email | D1 acté. Pas de fallback bailleur. |
| Renvoi avec confirmation | D2 acté. Dialog si `sent_at IS NOT NULL`. |
| Masquage email UI | RGPD : `"j***@example.com"` (premier char + 3 étoiles + domaine complet). Affiché en SnackBar et dans dialog confirmation. |
| Signed URL expiry interne | 60 secondes (vs 300 pour l'UI). L'Edge Function fetch immédiat, pas besoin de buffer. |
| Logs sans PII | Jamais `tenant.email` / `landlord.full_name` / contenu HTML. UUIDs et codes Resend uniquement. |
| Schema multi-env | `schema` field dans body, propagé à toutes les queries `.schema()`. Storage bucket partagé. |
| Vérifier JWT | `verify_jwt = true` (défaut). Cohérent avec `generate-receipt`. |
| Receipt mute lors d'envoi RPC échoué après mail | Log critique, return 200 quand même. Évite le double-mensonge "réessayer = double email". |

---

## 6. Plan de tests

### 6.1 Tests Deno (`supabase/functions/send-receipt/tests/`)

Pattern strictement aligné `generate-receipt/tests/*` (existant). Framework : `deno test --allow-net --allow-env`.

| Fichier | Couverture | Tests |
|---|---|---|
| `input_validation_test.ts` | `receipt_id` manquant, format UUID invalide, schema invalide, méthode != POST | 6 |
| `tenant_no_email_test.ts` | `tenants.email IS NULL` → 422 `tenant_no_email` ; email vide trim → 422 | 2 |
| `receipt_invalid_test.ts` | `is_voided = true` → 422 ; `is_stale = true` → 422 ; `pdf_path IS NULL` → 422 `pdf_unavailable` | 3 |
| `cross_user_404_test.ts` | User B invoque avec receipt_id de User A → 404 `receipt_not_found` (pas 403 — pas de leak) | 2 |
| `resend_quota_429_test.ts` | Mock Resend fetch retourne 429 → Edge Function retourne 429 `quota_exceeded` ; mock 5xx → 500 `email_send_failed` ; mock 401 (clé révoquée) → 500 `email_send_failed` + log critique | 3 |
| `email_template_test.ts` | Sujet contient "mai 2026" pour `period_start = 2026-05-01` ; corps contient `tenant.first_name`, montant formaté FR, mention loi 1989 ; caractères é/è/ç/€ encodés UTF-8 corrects | 4 |

**Cible** : ~20 tests Deno. **Pas de test "success path complet" avec Resend réel** au MVP (sandbox utilisé en QA manuel — cf. §6.4).

### 6.2 Tests SQL RLS (`supabase/tests/rls_receipts_send.sql`)

Nouveau fichier (ne pas polluer `rls_receipts.sql` existant).

| # | Test | Attendu |
|---|---|---|
| 1 | `mark_receipt_as_sent(<own valid id>, 'a@b.fr')` | Success + row updated |
| 2 | `mark_receipt_as_sent(<other landlord's id>, 'a@b.fr')` | ERRCODE P0002 (`not found, voided, stale, or not owned`) |
| 3 | `mark_receipt_as_sent(<own voided id>, 'a@b.fr')` | ERRCODE P0002 |
| 4 | `mark_receipt_as_sent(<own stale id>, 'a@b.fr')` | ERRCODE P0002 |
| 5 | `mark_receipt_as_sent(<own id>, NULL)` | ERRCODE 22023 |
| 6 | `mark_receipt_as_sent(<own id>, 'invalide')` | ERRCODE 22023 (regex fail) |
| 7 | `UPDATE receipts SET sent_at = now() WHERE id = ...` (sans flag) | ERRCODE 42501 (trigger protect) |
| 8 | `UPDATE receipts SET sent_to_email = '...' WHERE id = ...` (sans flag) | ERRCODE 42501 |
| 9 | Idempotence : appel #1 OK, appel #2 sur même receipt → met à jour `sent_at` (timestamp + récent) | 2 timestamps ≠ |
| 10 | Vérif policies : authenticated voit `sent_at` dans SELECT (déjà couvert par `receipts_select_own`) | row contient sent_at non-null |
| 11 | RLS active two schemas | `dev.assert_rls_both_schemas('receipts')` passe |

**Cible** : ~11 tests SQL.

### 6.3 Tests Flutter

| Fichier | Type | Couverture |
|---|---|---|
| `test/unit/send_receipt_state_test.dart` | unit | freezed equality + pattern matching sealed |
| `test/unit/edge_function_error_mapper_send_test.dart` | unit | mapping `tenant_no_email`, `receipt_invalid`, `pdf_unavailable`, `quota_exceeded` |
| `test/unit/receipts_repository_send_test.dart` | unit | mock `Db.invokeFunction` → success / 422 / 429 / FunctionException |
| `test/unit/send_receipt_controller_test.dart` | unit | transitions idle → submitting → success ; idle → confirmingResend si `hasBeenSent` ; tenantNoEmail ; rateLimited |
| `test/widget/send_receipt_button_test.dart` | widget | icon différent si hasBeenSent ; disabled si voided/stale ; clic ouvre dialog si confirmingResend ; SnackBar success ; SnackBar tenantNoEmail |

**Cible** : ~5 fichiers Flutter, ~25 tests cumulés.

### 6.4 QA manuel (sandbox Resend)

- Compte Resend sandbox (emails interceptés, dashboard preview)
- Scénarios :
  1. Premier envoi → email reçu en sandbox, PDF joint correct, sujet correct, corps lisible mobile + desktop
  2. Renvoi → dialog confirmation, after confirm email re-envoyé, `sent_at` mis à jour
  3. Tenant sans email → SnackBar visible, pas d'envoi
  4. Receipt void → bouton grisé, pas de tap actif
  5. Receipt stale → idem void
  6. Cross-user (2 comptes) → User B ne voit pas la receipt de User A (déjà couvert FEAT-007), tentative directe API → 404
  7. Quota dépassé : forcer en mockant le compte staging à un quota = 0 (pas trivial — alternative : intercepter via test Deno)
  8. Bundle Flutter : `flutter build web --release` puis grep `re_` dans `build/web/main.dart.js` → 0 résultat

---

## 7. Plan de migration

**Nom** : `supabase/migrations/<timestamp>_feat008_email_quittance.sql` (timestamp à figer par `supabase-dev`).

**Structure** (ordre, idempotente) :
1. `BEGIN;`
2. Section 1 — `ALTER TABLE public.receipts ADD COLUMN sent_at timestamptz NULL`, `ADD COLUMN sent_to_email text NULL`, + CHECK constraint `receipts_sent_consistency`
3. Section 2 — Identique pour `dev.receipts`
4. Section 3 — Fonction `public.protect_sent_columns_receipts()` + trigger `tr_01b_protect_sent_columns_receipts` BEFORE UPDATE
5. Section 4 — Identique pour `dev.protect_sent_columns_receipts()` + trigger
6. Section 5 — RPC `public.mark_receipt_as_sent(uuid, text)` + REVOKE/GRANT
7. Section 6 — Identique pour `dev.mark_receipt_as_sent(uuid, text)`
8. Section 7 — `SELECT dev.assert_rls_both_schemas('receipts');` (sanity check final)
9. `COMMIT;`

**Toutes les CREATE / ALTER doivent être IF NOT EXISTS / OR REPLACE** (rejouabilité).

---

## 8. Découpage en commits suggéré

1. `feat(receipts): migration sent_at + sent_to_email + RPC mark_receipt_as_sent` — SQL pur (~150 lignes)
2. `feat(receipts): edge function send-receipt (Resend + email template FR)` — Deno (~6 fichiers, ~500 lignes + tests)
3. `feat(receipts): domain Receipt model extension (sentAt/sentToEmail) + freezed regen` — Flutter (~3 fichiers + générés)
4. `feat(receipts): repository sendReceipt + edge_function_error_mapper extensions` — Flutter (~2 fichiers modifiés)
5. `feat(receipts): send_receipt_controller + send_receipt_state` — Flutter (~3 fichiers nouveaux)
6. `feat(receipts): send_receipt_button + confirm_resend_dialog + integrate in receipt_list_tile` — Flutter UI (~3 fichiers)
7. `test(receipts): RLS tests mark_receipt_as_sent + flutter tests send button` — Tests (~6 fichiers)
8. `chore(state): refresh state cache post-FEAT-008` — INDEX.md + SCHEMA.md + FUNCTIONS.md + FEATURES.md

**Ordre d'exécution** :
1. Migration (`supabase-dev`)
2. Provisionner secrets `RESEND_API_KEY` + `RESEND_FROM_EMAIL` staging
3. Edge Function (`supabase-dev` deploy)
4. Flutter (`flutter-dev`)
5. Tests (`qa-tester`)
6. Review (`code-reviewer` + `security-auditor` — focus sur audit secrets bundle + RLS)
7. State refresh (`state-keeper`)

---

## 9. Risques et points de vigilance

### Risques majeurs

1. **Domaine Resend non vérifié au moment du dev** → mails rejetés silencieusement. Mitigation : utiliser sandbox Resend (preview UI) ; bloquer release prod tant que domaine vérifié.
2. **Secret `RESEND_API_KEY` fuité côté client** → grosse facture potentielle (spam envoyé). Mitigation : (a) jamais bundlé, (b) audit bundle (`grep re_ build/web/`) en CI, (c) garder secret en Edge Function uniquement, (d) monitoring Resend dashboard.
3. **PDF lourd (> 5MB) → body Resend trop gros** → 413. Mitigation : log size, return 422 explicite "PDF trop volumineux" si > 30MB (limite Resend ~40MB). En MVP les quittances font < 100KB, risque très faible.
4. **Edge Function timeout sur fetch PDF si Storage lent** → 504. Mitigation : signed URL 60s + fetch direct (< 500ms typique). Si problème en prod, ajouter retry avec backoff.
5. **Race condition double-clic** : si le bailleur double-clique rapidement, deux requêtes parallèles envoient deux mails. Mitigation : (a) `state == submitting` désactive le bouton côté UI, (b) idempotence côté serveur **non** prévue (double-clic = double mail accepté pour MVP). Documentation user "ne cliquez qu'une fois".
6. **RPC échoue après email envoyé** : géré §3.5 step 12 (log critique, return 200, sent_at non persisté). Compromis acceptable pour MVP. P1 : ajouter `retry_pending_persist` cron.
7. **Caractères français dans le template** : email_template.ts doit utiliser `text/html; charset=UTF-8`. Pas de soucis sur les caractères Latin-1, mais tester explicitement « œ », « € », apostrophe typo « ' ». Couvert par `email_template_test.ts`.
8. **Resend API key révoquée en prod** → 401 Resend → tous les envois cassent silencieusement. Mitigation : log critique `[email-send-failed] reason=401` + alerte ops (monitoring dashboard Resend).
9. **Tenant change d'email après envoi** : `sent_to_email` reste figé sur la valeur au moment de l'envoi (snapshot audit). C'est voulu — pas un bug.

### Questions techniques critiques restantes

Aucune bloquante. Toutes les décisions produit (D1-D5) sont actées.

Sujets mineurs à confirmer en code review :
- **Resend message ID stocké ou pas ?** Le plan prévoit de le retourner au client mais pas de le persister. Si on veut tracer en cas de litige (preuve de remise), il faudrait l'ajouter à `receipts.resend_message_id text NULL`. **Recommandation** : pas au MVP (la mention `sent_at` suffit pour invocation art. 21). En P1 si litige réel survient.
- **Texte exact du corps du mail** : valider la formulation FR par le PO avant codage. Esquisse proposée § 3.5 step 10 — suffit pour démarrer mais le PO peut vouloir affiner.

---

## 10. Récap files créés / modifiés

### Nouveaux fichiers (SQL — 2)
- `supabase/migrations/<timestamp>_feat008_email_quittance.sql`
- `supabase/tests/rls_receipts_send.sql`

### Nouveaux fichiers (Edge Function — 11)
- `supabase/functions/send-receipt/index.ts`
- `supabase/functions/send-receipt/deps.ts`
- `supabase/functions/send-receipt/deno.json`
- `supabase/functions/send-receipt/email_template.ts`
- `supabase/functions/send-receipt/resend_client.ts`
- `supabase/functions/send-receipt/types.ts`
- `supabase/functions/send-receipt/tests/input_validation_test.ts`
- `supabase/functions/send-receipt/tests/tenant_no_email_test.ts`
- `supabase/functions/send-receipt/tests/receipt_invalid_test.ts`
- `supabase/functions/send-receipt/tests/cross_user_404_test.ts`
- `supabase/functions/send-receipt/tests/resend_quota_429_test.ts`
- `supabase/functions/send-receipt/tests/email_template_test.ts`

### Nouveaux fichiers (Flutter — 4 + générés)
- `lib/features/receipts/domain/send_receipt_state.dart` (+ `.freezed.dart`)
- `lib/features/receipts/application/send_receipt_controller.dart`
- `lib/features/receipts/presentation/widgets/send_receipt_button.dart`
- `lib/features/receipts/presentation/widgets/confirm_resend_dialog.dart`

### Nouveaux fichiers (tests Flutter — 5)
- `test/unit/send_receipt_state_test.dart`
- `test/unit/edge_function_error_mapper_send_test.dart`
- `test/unit/receipts_repository_send_test.dart`
- `test/unit/send_receipt_controller_test.dart`
- `test/widget/send_receipt_button_test.dart`

### Fichiers modifiés (Flutter — 3)
- `lib/features/receipts/domain/receipt.dart` (+ regénérer `.freezed.dart` / `.g.dart`)
- `lib/features/receipts/data/receipts_repository.dart` (méthode `sendReceipt` + exceptions)
- `lib/core/utils/edge_function_error_mapper.dart` (4 nouveaux codes + exceptions)
- `lib/features/receipts/presentation/widgets/receipt_list_tile.dart` (insérer `SendReceiptButton`)

### Fichiers modifiés (config + state — 5+)
- `supabase/config.toml` (déclarer la fonction `send-receipt` si nécessaire)
- `docs/state/INDEX.md`, `docs/state/SCHEMA.md`, `docs/state/FUNCTIONS.md`, `docs/state/FEATURES.md` (post-merge par `state-keeper`)

**Total estimé** : ~22 fichiers nouveaux + ~4 modifiés.

---

## 11. Estimation

**Priorité** : P0 (MVP)

**Effort total** : M (1,5-2,5 jours)

Décomposition (alignée story §Estimation) :
- Migration SQL + RPC + RLS tests : 0,25 jour
- Edge Function `send-receipt` + tests Deno : 0,75 jour
- Provisioning secrets + domaine Resend (infra) : 0,25 jour (suppose domaine déjà vérifié — sinon +0,5j)
- Flutter (controller, button, dialog, mapper, tests) : 0,75 jour
- QA sandbox + bundle audit + review : 0,25 jour

---

## 12. Questions à valider avant codage

Aucune question bloquante — toutes les décisions produit (D1-D5) sont actées.

Points à confirmer non bloquants (peuvent être tranchés en review) :
1. **Texte exact corps email FR** — esquisse fournie §3.5 step 10. PO peut affiner la formulation avant merge.
2. **`from` exact** : `noreply@<domaine>` ou `quittances@<domaine>` ? Choix cosmétique. Recommandation : `noreply` (signal clair pas de reply).
3. **Persister `resend_message_id`** dans `receipts` ? Recommandation : non au MVP, ajouter colonne en P1 si litige.
4. **Le bouton "Modifier la fiche locataire" dans la SnackBar `tenantNoEmail`** : navigation directe vers `tenant_edit` ? Si la route existe et accepte le tenant_id à dériver depuis le lease, oui. Sinon laisser uniquement le message. À vérifier au moment du codage Flutter.
