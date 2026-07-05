# Plan — [FEAT-009] Upload & stockage de documents

> Source story : [`docs/backlog/009-documents-storage.md`](../backlog/009-documents-storage.md)
> Patterns de référence :
> - SQL + bucket + RLS : [`docs/plans/FEAT-007-quittance-pdf.md`](FEAT-007-quittance-pdf.md)
> - Sealed state controller, mapper d'erreurs, GUC trigger : [`docs/plans/FEAT-008-email-quittance.md`](FEAT-008-email-quittance.md)
>
> **Décisions produit actées par l'utilisateur** :
> - **D1 = B** — validation MIME via Storage policy Supabase (whitelist PDF/JPEG/PNG/WEBP). Pas d'Edge Function.
> - **D2 = B** — warning soft à 100 MB par landlord (somme `size_bytes` côté Flutter). Pas de blocage hard.
> - **D3 modifié** — mécanisme `legal_hold` calculé par trigger sur `category IN ('bail_signe', 'etat_des_lieux')`. Si `legal_hold = true` au soft-delete, le fichier RESTE en Storage ; sinon hard-delete coordonné côté frontend.
> - **D4 = B** — seule `category` est UPDATE-able. `filename`, `storage_path`, `mime_type`, `size_bytes`, `legal_hold` protégés par trigger column protection.
> - **D5 modifié** — multi-upload MVP : `file_picker` (`allowMultiple: true`) + drag&drop Web via `DragTarget` Flutter natif.

---

## 1. Vue d'ensemble

**Objectif** : permettre au bailleur d'uploader, lister, recatégoriser, télécharger et supprimer des documents (PDF, JPEG, PNG, WEBP, max 10 MB) liés à un bail, dans un bucket Storage privé `documents`, avec audit/protection des fichiers à valeur juridique (bail signé, état des lieux) via un mécanisme `legal_hold`.

**Dépendances** :
- FEAT-001/002 (auth, RLS, soft-delete RPC pattern, GUC `app.allow_deleted_at_change`)
- FEAT-005 (`LeaseDetailPage`, modèle `Lease`)
- FEAT-007 (pattern bucket Storage privé + policy `storage.foldername(name)[…]` + helper `Db.storagePath`)
- FEAT-008 (pattern trigger `tr_01b_protect_…` à GUC + sealed state controller + extension `mapPostgrestError`)

**Débloque** : page globale `/documents` (P1), preview inline (P1), partage par email locataire (P2).

**Scope** :
- Table `public.documents` + `dev.documents` (12 colonnes, 3 index, 2 policies, 4 triggers)
- RPC `public.soft_delete_document(p_id uuid)` + `dev.soft_delete_document(p_id uuid)` — gère `legal_hold` (soft-only) vs hard-delete coordonné (retourne `storage_path` au frontend)
- Bucket Storage `documents` : privé, MIME whitelist serveur, max 10 MB, 4 policies (SELECT/INSERT/UPDATE/DELETE bouchées sur `(storage.foldername(name))[2] = auth.uid()`)
- Module Flutter `lib/features/documents/` (domain + data + application + presentation)
- Extension `mapPostgrestError` pour les nouveaux codes (legal_hold info, CHECK MIME, CHECK size)
- 2 nouvelles dépendances Flutter : `file_picker`, `mime`
- Tests : SQL RLS (~14), unit (~10), widget (~8)

**Hors scope** (cohérent story §Hors scope) :
- Page globale `/documents` cross-baux
- Preview inline (PDF renderer, image viewer) → ouverture nouvel onglet uniquement
- Documents rattachés directement à property/tenant/landlord (sans bail)
- Versionning / remplacement de document
- Office (.docx, .xlsx) hors whitelist
- OCR / extraction de données
- Corbeille / restauration

---

## 2. Modèle de données — `documents` (public + dev)

### 2.1 Colonnes

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PK, DEFAULT `gen_random_uuid()` |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` ON DELETE RESTRICT — dénormalisé pour RLS |
| `lease_id` | `uuid` | NOT NULL, FK → `leases(id)` ON DELETE RESTRICT |
| `category` | `public.document_category` | NOT NULL — enum (cf. §2.2) |
| `filename` | `text` | NOT NULL, CHECK `char_length BETWEEN 1 AND 255` — nom original du picker |
| `storage_path` | `text` | NOT NULL, CHECK `char_length BETWEEN 10 AND 512` — chemin complet dans le bucket |
| `mime_type` | `text` | NOT NULL, CHECK IN (`'application/pdf'`, `'image/jpeg'`, `'image/png'`, `'image/webp'`) |
| `size_bytes` | `integer` | NOT NULL, CHECK `> 0 AND <= 10485760` (10 MB) |
| `legal_hold` | `boolean` | NOT NULL DEFAULT `false` — calculé par trigger `tr_00b_compute_legal_hold` (cf. §2.4) |
| `uploaded_at` | `timestamptz` | NOT NULL DEFAULT `now()` — distinct de `created_at` (sémantique : "fichier reçu" vs "row créée") |
| `created_at` | `timestamptz` | NOT NULL DEFAULT `now()` |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT `now()` (trigger `tr_02_set_updated_at_documents`) |
| `deleted_at` | `timestamptz` | NULL — soft-delete via RPC `soft_delete_document()` uniquement |

**Pas de colonne `uploaded_by`** : redondant avec `landlord_id` (auth.uid() au moment de l'INSERT — vérifié par RLS). Pas d'usage produit pour distinguer "qui" dans un compte mono-utilisateur.

### 2.2 Nouveau type `document_category`

```sql
CREATE TYPE public.document_category AS ENUM (
  'bail_signe',
  'etat_des_lieux',
  'attestation_assurance',
  'quittance_scannee',
  'autre'
);
CREATE TYPE dev.document_category AS ENUM (
  'bail_signe', 'etat_des_lieux', 'attestation_assurance', 'quittance_scannee', 'autre'
);
```

Pattern aligné `public.document_type` (FEAT-007).

**Rationale enum vs CHECK text** : meilleure intégrité, IDE-friendly côté Edge Functions (auto-complétion TypeScript), ordre stable des valeurs.

### 2.3 Indexes

```
idx_public_documents_landlord_id_deleted   (landlord_id, deleted_at)
idx_public_documents_lease_active          (lease_id, deleted_at, uploaded_at DESC)
idx_public_documents_landlord_quota        (landlord_id) WHERE deleted_at IS NULL
```
Miroirs `idx_dev_documents_*`.

**Rationale** :
- `(landlord_id, deleted_at)` : index composite pour RLS (`landlord_id = auth.uid() AND deleted_at IS NULL`)
- `(lease_id, deleted_at, uploaded_at DESC)` : requête principale "liste documents d'un bail triés"
- `(landlord_id) WHERE deleted_at IS NULL` : index partiel pour la requête quota (`SUM(size_bytes)` filtré actif) — cardinalité faible, partial = optimal

### 2.4 Triggers

Pattern strictement aligné FEAT-007 (`tr_00`, `tr_01`, `tr_02` ordre alphabétique stable).

#### `tr_00_assert_documents_lease_ownership` BEFORE INSERT

- Fonction `public.assert_document_lease_ownership()` SECURITY DEFINER + `SET search_path = public`
- Valide : (a) `lease_id` existe dans `public.leases`, (b) `lease.landlord_id = NEW.landlord_id`
- Bail soft-deleted toléré (un bailleur peut uploader un document de référence sur un bail archivé)
- ERRCODE 23514 ("Document lease ownership mismatch")
- Miroir `dev.assert_document_lease_ownership()`
- Pattern strict de [`assert_payment_lease_ownership()`](../../supabase/migrations/20260531102202_feat006_payments.sql) et `assert_receipt_lease_ownership()` (FEAT-007)

#### `tr_00b_compute_legal_hold` BEFORE INSERT

- Fonction `public.compute_document_legal_hold()` (pas SECURITY DEFINER — pure logique sur NEW)
- Logique : `NEW.legal_hold := (NEW.category IN ('bail_signe', 'etat_des_lieux'))`
- Toujours appliqué : si un client envoie `legal_hold = true` pour `category = 'autre'`, on l'écrase à `false`. Si un client envoie `legal_hold = false` pour `category = 'bail_signe'`, on l'écrase à `true`. **La catégorie est source de vérité** (cf. décision D3 modifiée).
- Miroir `dev.compute_document_legal_hold()`

#### `tr_01_prevent_protected_columns_change_documents` BEFORE INSERT OR UPDATE

- Réutilise `public.prevent_protected_columns_change()` (FEAT-002) : bloque `deleted_at` direct (sauf GUC), `created_at` immuable, force `updated_at := OLD.updated_at`

#### `tr_01b_protect_immutable_documents` BEFORE UPDATE

- Nouveau trigger dédié, pattern strict de `tr_01b_protect_sent_columns_receipts` (FEAT-008)
- Protège **5 colonnes** : `filename`, `storage_path`, `mime_type`, `size_bytes`, `legal_hold`
- Aucun GUC bypass : ces colonnes ne doivent JAMAIS être réécrites après INSERT (même pas par RPC). `legal_hold` se gère via DELETE+INSERT si le bailleur veut changer la catégorie d'un fichier `bail_signe` → `autre` (refusé en pratique, cf. §2.5 UPDATE policy).
- Fonction `public.protect_immutable_documents()` :
  ```sql
  IF NEW.filename       IS DISTINCT FROM OLD.filename
     OR NEW.storage_path IS DISTINCT FROM OLD.storage_path
     OR NEW.mime_type    IS DISTINCT FROM OLD.mime_type
     OR NEW.size_bytes   IS DISTINCT FROM OLD.size_bytes
     OR NEW.legal_hold   IS DISTINCT FROM OLD.legal_hold
  THEN
    RAISE EXCEPTION 'columns filename/storage_path/mime_type/size_bytes/legal_hold are immutable on documents'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
  ```
- Miroir `dev.protect_immutable_documents()`

**Note legal_hold** : puisque `tr_00b` calcule `legal_hold` à partir de `category` à l'INSERT, et que `tr_01b` bloque tout changement, un UPDATE de `category` (`bail_signe` → `autre` par exemple) **ne touchera pas** `legal_hold`. Voulu : on ne veut pas qu'un bailleur dégrade le `legal_hold` d'un fichier déjà uploadé en jouant sur la catégorie. **Workaround si reclassement vraiment souhaité** : supprimer + ré-uploader (et le hard-delete sera bloqué par `legal_hold = true` → soft-delete uniquement).

#### `tr_02_set_updated_at_documents` BEFORE UPDATE

- Réutilise `public.set_updated_at()` (FEAT-001)

### 2.5 Policies RLS

| Policy | Op | Condition |
|---|---|---|
| `documents_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `documents_insert_own` | INSERT | WITH CHECK `landlord_id = auth.uid()` |
| `documents_update_category_own` | UPDATE | USING `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK `landlord_id = auth.uid()` |

**Le verrouillage "seule `category` est UPDATE-able"** est garanti par `tr_01b_protect_immutable_documents` : la policy RLS autorise techniquement `UPDATE * SET …`, mais le trigger refuse toute modification hors `category` (et `updated_at` géré par `tr_02`). C'est strictement aligné FEAT-008 (`mark_receipt_as_sent` : pas de policy UPDATE, contrôle 100% trigger/RPC).

**Pas de policy DELETE** : suppression via RPC `soft_delete_document` uniquement (§2.6).

### 2.6 RPC `soft_delete_document(p_id uuid) RETURNS TABLE(storage_path text, hard_deleted boolean)`

Pattern aligné `soft_delete_payment` (FEAT-006) + `void_receipt` (FEAT-007), avec sortie enrichie pour orchestrer le hard-delete Storage côté frontend.

```sql
CREATE OR REPLACE FUNCTION public.soft_delete_document(p_id uuid)
RETURNS TABLE (storage_path text, hard_deleted boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_legal_hold boolean;
  v_storage_path text;
BEGIN
  -- Lock + ownership + récupération atomique
  SELECT d.legal_hold, d.storage_path
    INTO v_legal_hold, v_storage_path
    FROM public.documents d
    WHERE d.id = p_id
      AND d.landlord_id = auth.uid()
      AND d.deleted_at IS NULL
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'document not found, not owned, or already deleted'
      USING ERRCODE = 'P0002';
  END IF;

  -- Pose GUC pour autoriser deleted_at update (cf. tr_01)
  PERFORM set_config('app.allow_deleted_at_change', '1', true);

  UPDATE public.documents
     SET deleted_at = now()
     WHERE id = p_id;

  -- Si legal_hold : fichier reste en Storage, frontend ne fait rien
  -- Sinon : frontend doit appeler storage.remove([storage_path])
  hard_deleted := NOT v_legal_hold;
  storage_path := CASE WHEN v_legal_hold THEN NULL ELSE v_storage_path END;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.soft_delete_document(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.soft_delete_document(uuid) TO authenticated;
```

Miroir `dev.soft_delete_document(uuid)`.

**Décision : hard-delete côté frontend** (cf. §10). Le retour `(storage_path, hard_deleted)` permet au client Flutter de :
1. Si `hard_deleted = false` → ne fait rien côté Storage (legal_hold ON, fichier conservé).
2. Si `hard_deleted = true` → appelle `supabase.storage.from('documents').remove([storage_path])` immédiatement.

**Compromis** : si le `storage.remove` échoue (rare — réseau, race), le fichier devient orphelin (la row DB est soft-deleted mais le binaire reste). Toléré au MVP, loggé côté Flutter avec logger `logging`, nettoyage manuel possible. Pattern strictement aligné [risque §9.4 FEAT-007 "orphan PDF"].

### 2.7 Vérification fin de migration

`SELECT dev.assert_rls_both_schemas('documents');`

---

## 3. Bucket Supabase Storage `documents`

### 3.1 Création (idempotente)

```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES (
    'documents',
    'documents',
    false,                              -- privé : jamais d'URL publique
    10485760,                           -- 10 MB max par fichier
    ARRAY[
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp'
    ]                                   -- D1 = B : MIME whitelist serveur
  )
  ON CONFLICT (id) DO NOTHING;
```

Pattern strict de la section 8 [`20260531172904_feat007_receipts.sql`](../../supabase/migrations/20260531172904_feat007_receipts.sql). `allowed_mime_types` est vérifié par Supabase Storage **au moment de l'upload** — un client qui ment sur le `contentType` sera rejeté côté serveur.

### 3.2 Structure de chemin

```
documents/{env_prefix}/{landlord_id}/{document_id}.{ext}
```

Exemple : `documents/prod/8e6c…/3a91….pdf` ou `documents/dev/8e6c…/3a91….jpg`.

**Divergence assumée vs FEAT-007 receipts** : `receipts` n'utilise PAS de préfixe d'env (`receipts/{landlord_id}/{receipt_id}.pdf` — voir [`20260531172904_feat007_receipts.sql` ligne 567](../../supabase/migrations/20260531172904_feat007_receipts.sql)). Pour `documents`, on adopte le pattern aligné `Db.storagePath()` (`{env_prefix}/{userId}/...`) parce que :
1. Les documents uploadés n'ont pas de besoin de rétention 5 ans transversale comme les quittances — l'isolation env stricte évite tout risque de leak dev→prod
2. Le helper `Db.storagePath('documents/<doc_id>.<ext>')` produit exactement `{env}/{uid}/documents/<doc_id>.<ext>` — on garde la cohérence Flutter (cf. §6.2)
3. Le préfixe segment `[1] = env` permet à terme un cleanup ciblé `WHERE name LIKE 'dev/%'`

**Conséquence policies** : la policy isolation est sur **segment [2]** (et non [1] comme dans receipts), à documenter explicitement dans la migration.

### 3.3 Policies Storage

```sql
-- SELECT : un user ne voit que ses propres documents (peu importe l'env)
DROP POLICY IF EXISTS "documents_storage_select_own" ON storage.objects;
CREATE POLICY "documents_storage_select_own" ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- INSERT : upload uniquement sous {env}/{auth.uid()}/...
DROP POLICY IF EXISTS "documents_storage_insert_own" ON storage.objects;
CREATE POLICY "documents_storage_insert_own" ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'documents'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- DELETE : hard-delete autorisé sous {env}/{auth.uid()}/... (orchestration RPC + frontend)
-- D3 modifié : la RPC soft_delete_document décide si hard_deleted=true (frontend appellera remove)
DROP POLICY IF EXISTS "documents_storage_delete_own" ON storage.objects;
CREATE POLICY "documents_storage_delete_own" ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

-- Pas d'UPDATE : si le bailleur veut "remplacer" un document, il en upload un nouveau et supprime l'ancien.
-- Évite les soucis de versionning + corruption de bytes invisible.
```

**Quatre policies au total** (SELECT + INSERT + DELETE — pas d'UPDATE). Pattern enrichi vs receipts (où DELETE est interdit pour rétention légale) : ici on accepte la suppression effective sauf legal_hold.

---

## 4. Quota par landlord (D2 = B — warning soft)

### 4.1 Côté DB

Aucun trigger, aucune fonction. La somme est calculée client-side via une requête Supabase classique :

```dart
final result = await Db.from('documents')
  .select('size_bytes')
  .eq('landlord_id', userId)
  .isFilter('deleted_at', null);
final totalBytes = (result as List).fold<int>(0, (acc, row) => acc + (row['size_bytes'] as int));
```

L'index partiel `idx_*_documents_landlord_quota` rend cette requête O(N) sur les docs actifs du landlord — acceptable jusqu'à plusieurs milliers de documents.

### 4.2 Côté UI

- Le `DocumentsQuotaProvider` (cf. §6.3) expose `quotaBytes / softLimitBytes (= 100 MB) / isOverSoftLimit`.
- À chaque ouverture de `DocumentsSection` et après chaque upload réussi, le provider est invalidé.
- Si `isOverSoftLimit == true` au moment où le bailleur clique "Ajouter" → SnackBar warning non-bloquant : `"Vous avez dépassé 100 Mo d'espace de stockage. Pensez à supprimer les documents obsolètes."` Le bouton reste actif.
- Pas de second seuil hard au MVP (cf. story §D2). Si Supabase free tier est saturé, le rejet viendra naturellement de l'upload Storage (erreur 413 ou 507) — mappé en message clair.

**Sécurité** : ce quota n'est PAS adversarial — un client malveillant pourrait l'ignorer. Acceptable pour un MVP B2C où le bailleur est l'opérateur et n'a aucun intérêt à se nuire. Quota hard via trigger (Option C de la story) est P1+.

---

## 5. Pas d'Edge Function

**Décision** : aucune Edge Function pour cette feature (D1 = B, D2 = B, D3 modifié).

**Justifications** :

1. **Validation MIME** (D1 = B) : faite par `allowed_mime_types` dans `storage.buckets` au moment de l'upload. Pas besoin d'inspection magic bytes serveur.
2. **Quota** (D2 = B) : calcul client. Pas de logique serveur.
3. **Hard-delete coordonné** (D3 modifié) : la RPC SECURITY DEFINER retourne `storage_path` au client, qui appelle `storage.from('documents').remove([…])`. L'alternative "Edge Function pour faire ce `remove`" ajoute :
   - Un cold-start (~200ms)
   - Une route HTTP supplémentaire à maintenir
   - Un secret service_role à manipuler côté serveur
   - Aucun gain sécurité (le client a déjà les droits DELETE via RLS Storage)

Si demain on ajoute l'envoi par email d'un document (à un assureur, à un comptable…), ce sera une Edge Function dédiée — pattern de FEAT-008.

---

## 6. Structure Flutter — `lib/features/documents/`

Pattern strict aligné [`lib/features/payments/`](../../lib/features/payments/) et [`lib/features/receipts/`](../../lib/features/receipts/).

```
lib/features/documents/
├── domain/
│   ├── document.dart                          # freezed + json_serializable
│   ├── document.freezed.dart                  # GÉNÉRÉ
│   ├── document.g.dart                        # GÉNÉRÉ
│   ├── document_category.dart                 # enum fromSql / sqlValue / label / requiresLegalHold
│   ├── documents_quota.dart                   # @freezed (totalBytes, softLimitBytes, isOverSoftLimit)
│   ├── documents_quota.freezed.dart           # GÉNÉRÉ
│   ├── upload_documents_state.dart            # sealed union freezed (cf. §6.4)
│   ├── upload_documents_state.freezed.dart    # GÉNÉRÉ
│   ├── upload_file_status.dart                # @freezed per-file: pending | uploading(progress) | success | error(msg)
│   └── upload_file_status.freezed.dart        # GÉNÉRÉ
├── data/
│   └── documents_repository.dart              # interface + SupabaseDocumentsRepository + provider Riverpod
├── application/
│   ├── lease_documents_provider.dart          # AsyncNotifierProvider.family<List<Document>, String leaseId>
│   ├── documents_quota_provider.dart          # AsyncNotifierProvider<DocumentsQuota>
│   ├── upload_documents_controller.dart       # StateNotifier autoDispose (multi-fichier)
│   ├── delete_document_controller.dart        # StateNotifier autoDispose (delete + hard-delete coordination)
│   └── update_document_category_controller.dart  # StateNotifier autoDispose
└── presentation/
    └── widgets/
        ├── documents_section.dart             # Intégré dans LeaseDetailPage (Column root)
        ├── documents_list.dart                # ListView builder + empty state
        ├── document_list_tile.dart            # filename + category chip + size + date + actions menu
        ├── upload_documents_drop_zone.dart    # DragTarget Web + bouton picker
        ├── document_category_chip.dart        # Chip avec label localisé + icon catégorie
        ├── edit_category_dialog.dart          # AlertDialog avec DropdownButton (5 catégories)
        ├── delete_document_dialog.dart        # AlertDialog confirmation + mention legal_hold si applicable
        └── upload_progress_list.dart          # BottomSheet ou Card listant le statut per-file pendant upload
```

### 6.1 Modèle `Document` (freezed)

```dart
@freezed
class Document with _$Document {
  const factory Document({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    @JsonKey(name: 'lease_id') required String leaseId,
    required DocumentCategory category,
    required String filename,
    @JsonKey(name: 'storage_path') required String storagePath,
    @JsonKey(name: 'mime_type') required String mimeType,
    @JsonKey(name: 'size_bytes') required int sizeBytes,
    @JsonKey(name: 'legal_hold') required bool legalHold,
    @JsonKey(name: 'uploaded_at') required DateTime uploadedAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Document;

  factory Document.fromJson(Map<String, dynamic> json) => _$DocumentFromJson(json);
}

extension DocumentX on Document {
  String get sizeHuman => /* "2,4 Mo" via formatBytesFr */;
  String get uploadedAtLabel => /* "01/06/2026" via FrenchDate.format */;
  String get extension => filename.split('.').last.toLowerCase();
  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';
}
```

### 6.2 Repository — méthodes

```dart
abstract interface class DocumentsRepository {
  Future<List<Document>> listForLease(String leaseId);
  Future<Document> getById(String id);
  Future<Document> upload({
    required String leaseId,
    required DocumentCategory category,
    required String filename,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  });
  Future<({String? storagePath, bool hardDeleted})> softDelete(String id);
  Future<Document> updateCategory({required String id, required DocumentCategory newCategory});
  Future<String> createSignedUrl(String storagePath, {int expiresInSeconds = 300});
  Future<DocumentsQuota> quotaForCurrentLandlord();
}
```

**Implémentation `upload`** :

1. **Génération UUID côté client** (`uuid` package déjà dans pubspec) → `docId`
2. **Construction du path** : `final relativePath = 'documents/$docId.$ext'; final storagePath = Db.storagePath(relativePath);` → `{env}/{uid}/documents/{docId}.{ext}` (aligné §3.2)
3. **Upload Storage** : `Supabase.instance.client.storage.from('documents').uploadBinary(storagePath, bytes, fileOptions: FileOptions(contentType: mimeType, upsert: false))`
4. **INSERT DB** : `Db.from('documents').insert({...}).select().single()` avec `id: docId`, `storage_path: storagePath`, etc.
5. **Si INSERT échoue** : appel `storage.from('documents').remove([storagePath])` pour rollback (best-effort, ne pas re-throw l'erreur du remove)
6. Retourne le `Document` parsé

**Implémentation `softDelete`** :

1. `final res = await Db.rpc('soft_delete_document', params: {'p_id': id});` retourne `[{ 'storage_path': '…' | null, 'hard_deleted': true | false }]`
2. Parse → si `hardDeleted == true && storagePath != null` → `Supabase.instance.client.storage.from('documents').remove([storagePath])` (best-effort, log si échoue)
3. Retourne le tuple `(storagePath, hardDeleted)` pour permettre au controller d'informer l'UI (« document conservé pour obligation légale » vs « document supprimé »)

**Implémentation `updateCategory`** : `Db.from('documents').update({'category': newCategory.sqlValue}).eq('id', id).select().single()`. RLS + trigger `tr_01b_protect_immutable_documents` garantissent que seul `category` change ; `tr_02_set_updated_at` met à jour `updated_at`.

**Implémentation `createSignedUrl`** : `Supabase.instance.client.storage.from('documents').createSignedUrl(storagePath, expiresInSeconds)`. Default 300s (5 min, aligné FEAT-007).

**Implémentation `quotaForCurrentLandlord`** : cf. §4.1.

### 6.3 Providers

| Provider | Type | Usage |
|---|---|---|
| `documentsRepositoryProvider` | `Provider<DocumentsRepository>` | Singleton wrapped autour Supabase client |
| `leaseDocumentsProvider(leaseId)` | `AsyncNotifierProvider.family<.., List<Document>, String>` | Liste filtrée par bail, `deleted_at IS NULL`, tri `uploaded_at DESC` |
| `documentsQuotaProvider` | `AsyncNotifierProvider<.., DocumentsQuota>` | Somme size_bytes pour landlord courant. Invalidé après upload/softDelete |
| `uploadDocumentsControllerProvider` | `StateNotifierProvider.autoDispose<.., UploadDocumentsState>` | Multi-fichier batch avec statut per-file |
| `deleteDocumentControllerProvider` | `StateNotifierProvider.autoDispose.family<.., DeleteDocumentState, String docId>` | Soft-delete + hard-delete coordination |
| `updateCategoryControllerProvider` | `StateNotifierProvider.autoDispose.family<.., UpdateCategoryState, String docId>` | Update catégorie + invalidate liste |
| `documentSignedUrlProvider(storagePath)` | `FutureProvider.family.autoDispose<String, String>` | Signed URL fresh à chaque tap (cohérent FEAT-007) |

Pattern d'invalidation après opération :
```dart
ref.invalidate(leaseDocumentsProvider(leaseId));
ref.invalidate(documentsQuotaProvider);
```

### 6.4 Sealed states

**`UploadDocumentsState`** (multi-fichier batch) :

```dart
@freezed
sealed class UploadDocumentsState with _$UploadDocumentsState {
  const factory UploadDocumentsState.idle() = UploadIdle;
  const factory UploadDocumentsState.uploading({
    required List<UploadFileStatus> files,  // ordre préservé du picker
  }) = Uploading;
  const factory UploadDocumentsState.completed({
    required int successCount,
    required int failureCount,
    required List<UploadFileStatus> files,  // pour reporting détaillé
  }) = UploadCompleted;
}
```

**`UploadFileStatus`** (par fichier individuel) :

```dart
@freezed
class UploadFileStatus with _$UploadFileStatus {
  const factory UploadFileStatus.pending({required String filename, required int sizeBytes}) = FilePending;
  const factory UploadFileStatus.uploading({required String filename, required double progress}) = FileUploading;
  const factory UploadFileStatus.success({required String filename, required Document document}) = FileSuccess;
  const factory UploadFileStatus.error({required String filename, required String message}) = FileError;
}
```

**`DeleteDocumentState`** :

```dart
@freezed
sealed class DeleteDocumentState with _$DeleteDocumentState {
  const factory DeleteDocumentState.idle() = DeleteIdle;
  const factory DeleteDocumentState.submitting() = DeleteSubmitting;
  const factory DeleteDocumentState.success({required bool hardDeleted}) = DeleteSuccess;
  const factory DeleteDocumentState.error({required String message}) = DeleteError;
}
```

**`UpdateCategoryState`** : `idle | submitting | success | error(message)` (pattern aligné FEAT-008 `SendReceiptState`).

### 6.5 Logique `UploadDocumentsController`

Méthode publique unique :

```dart
Future<void> uploadFiles({
  required String leaseId,
  required List<({String filename, Uint8List bytes, String mimeType, int sizeBytes})> pickedFiles,
  required DocumentCategory defaultCategory, // dialog avant batch : "Catégorie pour tous ces fichiers"
});
```

**Workflow** :

1. **Validations préalables** (rejet immédiat, pas d'appel réseau) :
   - Pour chaque fichier : `sizeBytes > 10 MB` → marqué `FileError("Le fichier dépasse 10 Mo.")`
   - Pour chaque fichier : `mimeType` hors whitelist → marqué `FileError("Format non supporté.")` (defense in depth via package `mime` côté client)
2. State = `Uploading(files: [FilePending, FilePending, ...])`
3. **Upload séquentiel** (pas parallèle pour MVP — évite saturation réseau + race conditions sur quota) :
   - Pour chaque fichier valide : `state → FileUploading(progress: 0.0)` puis appel `repo.upload(...)` (Supabase Storage ne supporte pas `onProgress` natif côté Flutter — on simule binaire 0% → 100% on completion ; vrai progress = P1)
   - Succès → `FileSuccess(document)`, échec → `FileError(message)` (mappé via `mapPostgrestError` + `mapStorageError` cf. §7)
4. À chaque transition de fichier, mise à jour `state` complet pour re-rendering progressif
5. À la fin → `state = UploadCompleted(...)` puis :
   - `ref.invalidate(leaseDocumentsProvider(leaseId))`
   - `ref.invalidate(documentsQuotaProvider)`
   - SnackBar récap : « 3 documents ajoutés (1 échec) » ou « 4 documents ajoutés »
6. `reset()` ramène à `idle` (appelé par le widget après affichage récap)

**Multi-fichier, même catégorie** : décision MVP — on demande UNE catégorie pour tout le batch (dialog d'amont). P1 : sélecteur de catégorie par fichier individuel. Évite un dialog de saisie par fichier au MVP.

### 6.6 Logique `DeleteDocumentController`

```dart
Future<void> delete({required String docId, required String leaseId}) async {
  state = const DeleteDocumentState.submitting();
  try {
    final result = await repo.softDelete(docId);
    state = DeleteDocumentState.success(hardDeleted: result.hardDeleted);
    ref.invalidate(leaseDocumentsProvider(leaseId));
    ref.invalidate(documentsQuotaProvider);
  } on PostgrestException catch (e) {
    state = DeleteDocumentState.error(message: mapPostgrestError(e));
  } catch (e, st) {
    _log.severe('Document delete failed', e, st);
    state = const DeleteDocumentState.error(message: 'Suppression impossible. Réessayez.');
  }
}
```

SnackBar selon `hardDeleted` :
- `true` → « Document supprimé. »
- `false` → « Document supprimé de la liste. Le fichier est conservé pour obligation légale. »

### 6.7 Widget `DocumentsSection` (intégration LeaseDetailPage)

Aligné le pattern existant `PaymentListSection` / `ReceiptsListSection` (cf. `lib/features/leases/presentation/lease_detail_page.dart:107-109`) — ajout d'une 3e section à la suite, sans TabBar :

```dart
class DocumentsSection extends ConsumerWidget {
  final String leaseId;
  // header "Documents" + UploadDocumentsDropZone + DocumentsList (ou empty state)
}
```

Modification de `lease_detail_page.dart` ligne ~110 : ajouter `DocumentsSection(leaseId: lease.id)` après `ReceiptsListSection`.

### 6.8 Widget `UploadDocumentsDropZone`

- **Bouton picker** (toujours visible) : `FilledButton.tonal.icon(label: 'Sélectionner des fichiers', icon: Icons.upload_file_outlined)` → ouvre `FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'], withData: true)`
- **Zone drag & drop Web** : `DragTarget<List<XFile>>` Flutter natif (depuis Flutter Web 3.7+) ou `DropTarget` selon ce qui marche le plus simplement. **Vérifier** au moment du codage : `DragTarget` natif ne capture pas les fichiers OS sur Web. Si bloqué : utiliser un `<input type="file">` invisible avec `html` + écouter `ondrop` via JS interop (overhead ~30 lignes), OU se contenter du picker pour le MVP et reporter le drag&drop natif en P1. **À trancher au début du dev** (cf. §11 question 3).
- Affiche le quota courant en bas : "Espace utilisé : 42 Mo / 100 Mo" (warning rouge si > 100 Mo)
- Dialog post-pick : `EditCategoryDialog` pour choisir la catégorie commune au batch

### 6.9 Widget `DocumentListTile`

Layout :
- `leading` : icon selon `mime_type` (`Icons.picture_as_pdf_outlined` rouge | `Icons.image_outlined` bleu)
- `title` : `filename`
- `subtitle` : `Wrap` avec `DocumentCategoryChip(category)` + ` · ${sizeHuman} · ${uploadedAtLabel}`
- `trailing` : `PopupMenuButton` avec actions :
  - "Télécharger" → tap → fetch signed URL → `launchUrl(url, mode: externalApplication)`
  - "Modifier la catégorie" → ouvre `EditCategoryDialog(currentCategory: …, onSelect: …)`
  - "Supprimer" → ouvre `DeleteDocumentDialog(document: …)` (qui affiche la mention legal_hold si applicable)

### 6.10 Empty state

Cohérent PR #18 (wording positif, couleur primary). Composant `Center` :

```
[Icon folder_open_outlined, size 64, color primary]
"Vos documents apparaîtront ici"
"Glissez vos fichiers ici ou cliquez pour sélectionner"
```

Le bouton picker reste visible juste sous l'empty state (la `UploadDocumentsDropZone` est toujours rendue, l'empty state s'affiche au-dessus quand `documents.isEmpty`).

### 6.11 Routes go_router

**Aucune nouvelle route** au MVP. Tout est intégré dans `LeaseDetailPage` (cohérent story §Hors scope "page globale /documents"). Le tap sur "Télécharger" ouvre le PDF/image dans un nouvel onglet via `launchUrl(externalApplication)` — pas de route interne.

---

## 7. Mapper d'erreurs

### 7.1 Extension `mapPostgrestError`

[`lib/core/utils/postgrest_error_mapper.dart`](../../lib/core/utils/postgrest_error_mapper.dart) doit être étendu pour reconnaître les nouveaux codes :

| ERRCODE | Message contenu | Mapping FR |
|---|---|---|
| `23514` | `mime_type` IN | « Format non supporté. Formats acceptés : PDF, JPG, PNG, WEBP. » |
| `23514` | `size_bytes` | « Ce fichier dépasse la limite de 10 Mo. » |
| `23514` | `Document lease ownership mismatch` | « Le bail n'existe pas ou ne vous appartient pas. » |
| `42501` | `columns filename/storage_path/mime_type/size_bytes/legal_hold are immutable` | « Ces propriétés du document ne peuvent pas être modifiées. » (cas anormal — bug client) |
| `P0002` | `document not found, not owned, or already deleted` | « Document introuvable ou déjà supprimé. » |

L'implémentation se fait par pattern matching sur `e.message` (ne pas casser les mappings existants des autres tables — chaque CHECK contient un libellé unique).

### 7.2 Helper `mapStorageError`

Nouveau fichier `lib/core/utils/storage_error_mapper.dart` (anticipation pour d'éventuelles future features). À minima pour FEAT-009 :

```dart
String mapStorageError(StorageException e) {
  switch (e.statusCode) {
    case '413': return 'Fichier trop volumineux (max 10 Mo).';
    case '415': return 'Format non supporté. Formats acceptés : PDF, JPG, PNG, WEBP.';
    case '409': return 'Un fichier portant ce nom existe déjà.';
    case '507': return 'Espace de stockage insuffisant.';
    default:
      return 'Erreur de stockage. Réessayez plus tard.';
  }
}
```

Utilisé par `repo.upload` (catch `StorageException`).

### 7.3 Pas de nouvelles exceptions typées

Contrairement à FEAT-008 (qui en ajoute 4), FEAT-009 n'en ajoute aucune. Les erreurs sont remontées via les mappers ci-dessus. L'UI reste simple : SnackBar avec le message FR retourné. Pattern aligné FEAT-006 (payments).

---

## 8. Helpers nouveaux ou réutilisés

| Helper | Statut |
|---|---|
| `FrenchDate.format` | Réutilisé ([`lib/core/utils/french_date.dart`](../../lib/core/utils/french_date.dart)) |
| `Db.from`, `Db.rpc`, `Db.storagePath` | Réutilisés ([`lib/core/db.dart`](../../lib/core/db.dart)) |
| `mapPostgrestError` | **Étendu** (cf. §7.1) |
| `mapStorageError` | **Nouveau** (cf. §7.2) |
| `formatBytesFr(int bytes) → String` | **Nouveau** dans `lib/core/utils/byte_format.dart` (FR : "2,4 Mo", "850 Ko"). Pattern aligné `MoneyFormat` |
| `Logger _log = Logger('Documents')` | Réutilisé (`logging` déjà en deps) |

---

## 9. Dépendances Flutter à ajouter

| Package | Version | Justification |
|---|---|---|
| `file_picker` | `^8.0.0` | Cross-platform (Web + mobile) picker avec `allowMultiple: true` et `withData: true` pour récupérer les bytes en mémoire (indispensable Web, pas de filesystem) |
| `mime` | `^1.0.5` | Détection MIME côté client à partir de l'extension (defense in depth — Storage policy reste source de vérité) |

**Pas de `desktop_drop`** : on cible Flutter Web, donc utilisation du `DragTarget` natif ou `<input type="file">` HTML pour le drag & drop. Si bloquant au moment du codage : reporter drag & drop en P1 et garder uniquement le picker (cf. §11 Q3).

**Mise à jour pubspec.yaml** :
```yaml
dependencies:
  file_picker: ^8.0.0
  mime: ^1.0.5
```

**Mise à jour CSP** : aucune. `file_picker` Web utilise l'input HTML natif, pas de connexion externe.

---

## 10. Décisions techniques

| Sujet | Décision | Justification |
|---|---|---|
| Validation MIME | Storage policy `allowed_mime_types` (D1=B) | Sans latence, contournement impossible, pas d'Edge Function à maintenir |
| Quota | Client-side warning soft à 100 MB (D2=B) | MVP B2C non-adversarial, complexité serveur évitée. Hard quota = P1 |
| Hard-delete fichier | Frontend-driven via RPC qui retourne `storage_path` (D3 modifié) | Évite Edge Function dédiée pour un `storage.remove()` ; le client a déjà la policy DELETE. Compromis orphelin si remove échoue (loggé, P2 cleanup job) |
| Legal hold | Trigger calcule `legal_hold = (category IN ('bail_signe', 'etat_des_lieux'))` (D3 modifié) | Évite double saisie / désynchro. La catégorie est source de vérité. Immutable après INSERT |
| Editable fields | Seulement `category` (D4=B) | `filename/storage_path/mime_type/size_bytes/legal_hold` protégés par `tr_01b_protect_immutable_documents`. Pas de policy UPDATE conditionnelle (pattern FEAT-008) |
| Multi-upload | `file_picker(allowMultiple: true)` + drag&drop Web best-effort (D5 modifié) | UX nettement améliorée pour MVP. Catégorie unique pour le batch (P1 = per-file) |
| Path Storage | `documents/{env}/{landlord_id}/{document_id}.{ext}` | Aligné `Db.storagePath()` + isolation env stricte (divergence assumée vs receipts) |
| Path isolation | `(storage.foldername(name))[2] = auth.uid()::text` | Conséquence du préfixe env en segment [1] |
| Signed URL TTL | 300 secondes (5 min) | Aligné FEAT-007. Réémission à chaque tap |
| Bucket privé | `public = false` | Cohérent receipts, jamais d'URL publique |
| Soft-delete via RPC SECURITY DEFINER | Oui, pattern aligné FEAT-006 | Atomicité ownership check + GUC + retour `storage_path` |
| Edge Function | **Aucune** | Toute la logique est SQL + client. Pas de PDF gen, pas d'email, pas de validation MIME serveur custom (storage policy suffit) |
| Enum `document_category` | Type SQL natif | Cohérent `document_type` (FEAT-007), validation forte |
| Upload séquentiel vs parallèle | Séquentiel | Évite race quota, simplifie reporting per-file, ~2s par doc 1 MB acceptable |
| Sélecteur catégorie multi-upload | Unique pour le batch | Évite N dialogs. Per-file = P1 |
| Pas de DELETE policy sur DB | Toujours RPC | Pattern unique aligné toutes les tables soft-deletables |
| `uploaded_at` distinct de `created_at` | Oui | Sémantique : "fichier reçu" (= moment upload Storage) vs "row écrite" (= INSERT DB). Mêmes valeurs en pratique mais sémantiquement disjoints |

---

## 11. ⚠️ Questions à valider avant codage

1. **Divergence path Storage vs FEAT-007 receipts** : le plan adopte `documents/{env}/{landlord_id}/...` (préfixe env) alors que `receipts/` n'utilise PAS de préfixe env. C'est intentionnel (cf. §3.2) mais **introduit une incohérence inter-feature** pour le futur lecteur de migrations. **Recommandation** : valider OK avec utilisateur (déjà acté implicitement via la spec fournie). Si on veut un alignement total, reformater FEAT-007 en P1 (out of scope ici).
2. **Multi-upload, catégorie unique pour le batch** : le plan suppose que le bailleur upload 3 documents de la même catégorie (typiquement "État des lieux" : 3 photos). **Est-ce un scénario UX réaliste ?** Si non, il faut un dialog catégorie **par fichier** (overhead UX). **Recommandation** : MVP avec catégorie unique + bouton "modifier la catégorie" individuel dans la liste après upload — un click supplémentaire reste tolérable.
3. **Drag & drop natif Flutter Web** : `DragTarget` Flutter ne capture pas les fichiers OS sur Web par défaut. Options : (a) JS interop via `dart:html` `addEventListener('drop')` (~30 lignes), (b) package `desktop_drop` (non testé en Web pur), (c) reporter drag&drop en P1. **Recommandation** : tenter (a) en début de codage avec timebox de 30 min — si échec, reporter à P1 et garder uniquement le picker. La story §AC ne mentionne pas le drag&drop comme bloquant.
4. **Limite picker `withData: true`** : `file_picker` charge tout le binaire en mémoire — un user qui sélectionne 50 PDF de 10 MB chacun va consommer 500 MB RAM avant qu'on rejette. **Mitigation** : limiter `pickedFiles.length <= 10` côté UI (si > 10 → message "Maximum 10 fichiers à la fois, recommencez en plusieurs lots."). À ajouter aux validations §6.5.
5. **`document_category` enum vs colonne `text` CHECK IN** : le plan choisit l'enum SQL natif (cohérent `document_type`). **Confirmer** : OK pour ajouter un type ENUM dédié plutôt que CHECK IN (pattern uniforme avec FEAT-007).
6. **Vraie barre de progression d'upload** : Supabase Storage `uploadBinary` ne supporte pas `onProgress` natif côté Dart (côté TS oui via XHR). Au MVP : binaire 0% / 100%. **Confirmer** : acceptable, vraie progress = P1.

Aucune de ces questions n'est bloquante pour démarrer — elles seront résolues au codage avec des défauts raisonnés. À flagger product-owner si besoin.

---

## 12. Plan de tests

### 12.1 Tests SQL RLS (`supabase/tests/rls_documents.sql`)

Pattern aligné [`rls_payments.sql`](../../supabase/tests/rls_payments.sql), [`rls_receipts.sql`](../../supabase/tests/rls_receipts.sql).

| # | Test | Attendu |
|---|---|---|
| 1 | User A insert document sur son propre lease | OK |
| 2 | User A insert document avec lease_id de User B | ERRCODE 23514 (trigger `assert_document_lease_ownership`) |
| 3 | User A select ses propres documents | rows retournés |
| 4 | User A select documents de User B | 0 rows |
| 5 | User A update `category` de son document | OK, `updated_at` bumpé |
| 6 | User A update `filename` de son document | ERRCODE 42501 (trigger `protect_immutable_documents`) |
| 7 | User A update `storage_path` | ERRCODE 42501 |
| 8 | User A update `legal_hold` directement | ERRCODE 42501 |
| 9 | User A DELETE direct → refusé (pas de policy) | DELETE 0 rows |
| 10 | INSERT avec mime_type hors whitelist → ERRCODE 23514 CHECK |
| 11 | INSERT avec size_bytes > 10485760 → ERRCODE 23514 CHECK |
| 12 | INSERT avec `category = 'bail_signe'` → trigger met `legal_hold = true` automatiquement |
| 13 | INSERT avec `category = 'autre'` + `legal_hold = true` envoyé par client → trigger force `legal_hold = false` |
| 14 | RPC `soft_delete_document` avec doc non-legal_hold → retourne `(storage_path, true)`, deleted_at posé |
| 15 | RPC `soft_delete_document` avec doc legal_hold → retourne `(NULL, false)`, deleted_at posé |
| 16 | RPC `soft_delete_document` cross-user → ERRCODE P0002 |
| 17 | RPC `soft_delete_document` sur doc déjà supprimé → ERRCODE P0002 |
| 18 | anon ne peut pas EXECUTE `soft_delete_document` → 42501 |
| 19 | `dev.assert_rls_both_schemas('documents')` passe |

**Cible** : ~19 tests SQL.

### 12.2 Tests Storage RLS (`supabase/tests/storage_documents.sql`)

| # | Test | Attendu |
|---|---|---|
| 1 | User A INSERT objet `documents/prod/<self>/foo.pdf` | OK |
| 2 | User A INSERT objet `documents/prod/<otherUser>/foo.pdf` | refused |
| 3 | User A SELECT objet `documents/prod/<otherUser>/foo.pdf` | 0 rows |
| 4 | User A DELETE objet `documents/prod/<self>/foo.pdf` | OK |
| 5 | User A DELETE objet `documents/prod/<otherUser>/foo.pdf` | refused |
| 6 | Upload `.docx` → refused par bucket `allowed_mime_types` |
| 7 | Upload 11 MB → refused par bucket `file_size_limit` |

**Cible** : ~7 tests Storage.

### 12.3 Tests Flutter

| Fichier | Type | Couverture |
|---|---|---|
| `test/unit/document_test.dart` | unit | freezed equality, JSON roundtrip, extensions (sizeHuman, isImage, isPdf) |
| `test/unit/document_category_test.dart` | unit | fromSql, sqlValue, label, requiresLegalHold |
| `test/unit/documents_quota_test.dart` | unit | isOverSoftLimit selon valeurs |
| `test/unit/byte_format_test.dart` | unit | formatBytesFr (octets, Ko, Mo, séparateur FR) |
| `test/unit/documents_repository_test.dart` | unit | mock Supabase client + storage : upload OK, upload + INSERT fail → rollback storage.remove appelé, softDelete avec/sans legal_hold |
| `test/unit/upload_documents_controller_test.dart` | unit | transitions idle → uploading(N pending) → uploading(progressif) → completed ; validation locale rejette > 10 MB et MIME hors whitelist |
| `test/unit/delete_document_controller_test.dart` | unit | success(hardDeleted=true) vs success(hardDeleted=false), erreurs mappées |
| `test/unit/update_category_controller_test.dart` | unit | submit OK + invalidate, erreur mappée |
| `test/unit/storage_error_mapper_test.dart` | unit | 413/415/507/default |
| `test/widget/documents_section_test.dart` | widget | empty state visible si vide, liste rendue si docs, drop zone toujours visible |
| `test/widget/document_list_tile_test.dart` | widget | rendu filename + chip + sizeHuman + dateLabel ; menu actions présent ; tap télécharger ouvre URL |
| `test/widget/upload_documents_drop_zone_test.dart` | widget | clic bouton picker (mock FilePicker), warning quota affiché si > 100 MB |
| `test/widget/edit_category_dialog_test.dart` | widget | 5 options affichées, sélection retournée |
| `test/widget/delete_document_dialog_test.dart` | widget | mention "Document conservé (obligation légale)" si legal_hold, sinon "Le fichier sera définitivement supprimé." |
| `test/widget/upload_progress_list_test.dart` | widget | rendu liste per-file selon états (pending / uploading / success / error) |

**Cible** : ~15 fichiers Flutter, ~50 tests cumulés.

### 12.4 QA manuel staging

1. Upload PDF 5 MB seul → liste mise à jour, télécharger ouvre nouvel onglet PDF lisible
2. Upload 4 fichiers (PDF + 3 images) en multi-pick avec catégorie "État des lieux" → 4 documents apparaissent, quota mis à jour
3. Drag & drop 2 fichiers (si implémenté) → idem #2
4. Upload `.docx` → message d'erreur clair (rejeté par Storage policy)
5. Upload PDF 11 MB → message d'erreur clair (rejeté côté client avant réseau)
6. Modifier catégorie d'un document `autre` → `attestation_assurance` → liste rafraîchie
7. Supprimer un document `autre` → SnackBar « supprimé », document retiré, taille quota baisse
8. Supprimer un document `bail_signe` → dialog mentionne legal_hold, SnackBar « conservé pour obligation légale », document retiré de la liste mais Storage object persiste (vérifier dashboard Supabase)
9. Cross-user (2 comptes) → user B ne voit pas les documents de A, signed URL généré par A pour son doc fonctionne pour A, ne fonctionne pas pour B (test direct API)
10. Upload 50 MB total → warning soft à 100 MB pas encore déclenché ; pousser à 110 MB → SnackBar warning à l'upload suivant

---

## 13. Plan de migration

**Nom** : `supabase/migrations/<timestamp>_feat009_documents_storage.sql` (timestamp figé par `supabase-dev`).

**Structure** (sections ordonnées, idempotent où pertinent) :

1. `BEGIN;`
2. Section 1 — `CREATE TYPE public.document_category` + `CREATE TYPE dev.document_category` (`IF NOT EXISTS` impossible sur ENUM → guard avec `DO $$ BEGIN ... EXCEPTION WHEN duplicate_object THEN null; END $$`)
3. Section 2 — Fonctions `public.assert_document_lease_ownership()` + `dev.assert_document_lease_ownership()` (SECURITY DEFINER)
4. Section 3 — Fonctions `public.compute_document_legal_hold()` + `dev.compute_document_legal_hold()`
5. Section 4 — Fonctions `public.protect_immutable_documents()` + `dev.protect_immutable_documents()`
6. Section 5 — Table `public.documents` + index + RLS + 3 policies + 4 triggers (tr_00, tr_00b, tr_01, tr_01b, tr_02)
7. Section 6 — Table `dev.documents` (miroir intégral) + index + RLS + policies + triggers
8. Section 7 — RPC `public.soft_delete_document(uuid)` + `dev.soft_delete_document(uuid)` (REVOKE/GRANT)
9. Section 8 — Bucket Storage `documents` : `INSERT INTO storage.buckets (...) ON CONFLICT DO NOTHING`
10. Section 9 — Policies Storage (`documents_storage_select_own`, `documents_storage_insert_own`, `documents_storage_delete_own`) avec `DROP POLICY IF EXISTS` puis `CREATE POLICY`
11. Section 10 — `SELECT dev.assert_rls_both_schemas('documents');` (sanity)
12. `COMMIT;`

**Convention multi-env** : changes appliqués aux deux schémas dans la même migration (cf. [`docs/ENVIRONMENTS.md`](../ENVIRONMENTS.md)).

---

## 14. Découpage en commits suggéré

1. `feat(documents): migration documents + RLS + triggers + bucket storage + RPC soft_delete_document` — SQL pur (~500 lignes)
2. `chore(deps): add file_picker + mime packages` — pubspec.yaml + lockfile
3. `feat(documents): domain Document + DocumentCategory + DocumentsQuota + sealed states + byte_format` — Flutter modèles + helpers (~10 fichiers + générés)
4. `feat(documents): repository SupabaseDocumentsRepository + extensions mapPostgrestError + storage_error_mapper` — Flutter data (~3 fichiers nouveaux + 1 modifié)
5. `feat(documents): providers lease_documents + documents_quota + controllers upload/delete/update_category` — Flutter application (~5 fichiers)
6. `feat(documents): UI DocumentsSection + DocumentsList + DocumentListTile + DocumentCategoryChip` — Flutter widgets de liste (~4 fichiers)
7. `feat(documents): UI UploadDocumentsDropZone + EditCategoryDialog + DeleteDocumentDialog + UploadProgressList` — Flutter widgets d'action (~4 fichiers)
8. `feat(documents): integrate DocumentsSection in LeaseDetailPage` — modif `lease_detail_page.dart` (1 fichier)
9. `test(documents): RLS + storage SQL tests` — `rls_documents.sql` + `storage_documents.sql` (~26 tests)
10. `test(documents): unit + widget Flutter tests` — ~15 fichiers tests (~50 tests)
11. `chore(state): refresh state cache post-FEAT-009` — INDEX.md + SCHEMA.md + FUNCTIONS.md + FEATURES.md + DEPENDENCIES.md

**Ordre d'exécution** :
1. Migration via `supabase-dev` (apply staging puis prod après QA)
2. Dépendances Flutter via `flutter-dev` (`flutter pub get`)
3. Implémentation Flutter via `flutter-dev` (commits 3-8)
4. Tests via `qa-tester` (commits 9-10)
5. Review via `code-reviewer` + `security-auditor` (focus sur RLS Storage + legal_hold + orphan handling)
6. State refresh via `state-keeper` (commit 11)

---

## 15. Risques et points de vigilance

### Risques majeurs

1. **Orphelin Storage si `storage.remove` échoue après soft-delete réussi** — DB en `deleted_at` set, fichier toujours en bucket. Toléré au MVP, loggué `[orphan-document] doc=<id> path=<storage_path>`. Cleanup P1 via cron + grep logs.
2. **`legal_hold` non révocable** — Un bailleur qui upload un faux "bail signé" puis veut le supprimer ne peut plus hard-delete le fichier (legal_hold ON). **Compromis assumé** : la rétention l'emporte sur la commodité. Workaround : un endpoint admin (out of MVP) pourrait force-delete. Documentation user à prévoir dans `/privacy`.
3. **Bypass MIME via Supabase Storage** — la validation `allowed_mime_types` se fait sur le Content-Type envoyé par le client, PAS sur les magic bytes du fichier. Un fichier `.exe` renommé `.pdf` avec `contentType: application/pdf` passera Supabase. Mitigation MVP : risk accepté (le bailleur est l'opérateur, pas l'attaquant). Hardening P1 : Edge Function de scan magic bytes (cf. D1 Option C de la story).
4. **Quota client-side contournable** — un user malveillant peut bypass le warning et exploser le free tier. Acceptable MVP (B2C non-adversarial). Monitoring Supabase dashboard pour détecter.
5. **`file_picker` Web charge en RAM** — 50 fichiers × 10 MB = 500 MB côté navigateur. Mitigation §11 Q4 : limiter `pickedFiles.length <= 10` côté UI.
6. **Drag & drop natif Flutter Web flaky** — `DragTarget` ne capture pas les fichiers OS par défaut. Cf. §11 Q3 — fallback acceptable au picker.
7. **Path Storage divergent vs `receipts`** — vu en §3.2 et §11 Q1. À documenter dans le commit pour éviter confusion future.
8. **Catégorisation imposée au moment de l'upload** — pas de catégorie "à classer plus tard". Mitigation : la catégorie par défaut `autre` joue ce rôle, et la modification ultérieure est gratuite (un click). OK MVP.
9. **Trigger `tr_01b_protect_immutable_documents` empêche tout migration de schéma douce** — si demain on veut renommer `filename` ou changer le `mime_type` programmatiquement (data migration), il faudra droper le trigger temporairement. Acceptable, pattern uniforme.
10. **Bail soft-deleted + INSERT toujours autorisé** — cohérent receipts. Si le bail est archivé, un bailleur peut quand même uploader un document (régularisation tardive, dossier juridique en cours). Pas un bug.

### Points de vigilance review

- **`security-auditor`** :
  - Vérifier qu'aucun secret n'est exposé (RPC n'a pas besoin de secret)
  - Vérifier que la signed URL TTL est bien à 300s (pas davantage)
  - Vérifier que la policy DELETE Storage n'est pas trop permissive (segment [2] strict)
  - Tester un cross-user direct API pour confirmer 0 leak
- **`code-reviewer`** :
  - Validation que `tr_01b_protect_immutable_documents` couvre les 5 colonnes
  - Validation que `documents_quota_provider` est bien invalidé après chaque mutation
  - Validation que `upload_documents_controller` n'effectue pas d'INSERT DB si upload Storage échoue
  - Validation que `softDelete` du repository appelle bien `storage.remove` UNIQUEMENT si `hardDeleted == true`

---

## 16. Récap files créés / modifiés

### Nouveaux fichiers (SQL — 2)
- `supabase/migrations/<timestamp>_feat009_documents_storage.sql`
- `supabase/tests/rls_documents.sql`
- `supabase/tests/storage_documents.sql`

### Nouveaux fichiers (Flutter domain — 5 + 4 générés)
- `lib/features/documents/domain/document.dart` (+ `.freezed.dart`, `.g.dart`)
- `lib/features/documents/domain/document_category.dart`
- `lib/features/documents/domain/documents_quota.dart` (+ `.freezed.dart`)
- `lib/features/documents/domain/upload_documents_state.dart` (+ `.freezed.dart`)
- `lib/features/documents/domain/upload_file_status.dart` (+ `.freezed.dart`)

### Nouveaux fichiers (Flutter data — 1)
- `lib/features/documents/data/documents_repository.dart`

### Nouveaux fichiers (Flutter application — 5)
- `lib/features/documents/application/lease_documents_provider.dart`
- `lib/features/documents/application/documents_quota_provider.dart`
- `lib/features/documents/application/upload_documents_controller.dart`
- `lib/features/documents/application/delete_document_controller.dart`
- `lib/features/documents/application/update_document_category_controller.dart`

### Nouveaux fichiers (Flutter presentation — 8)
- `lib/features/documents/presentation/widgets/documents_section.dart`
- `lib/features/documents/presentation/widgets/documents_list.dart`
- `lib/features/documents/presentation/widgets/document_list_tile.dart`
- `lib/features/documents/presentation/widgets/document_category_chip.dart`
- `lib/features/documents/presentation/widgets/upload_documents_drop_zone.dart`
- `lib/features/documents/presentation/widgets/edit_category_dialog.dart`
- `lib/features/documents/presentation/widgets/delete_document_dialog.dart`
- `lib/features/documents/presentation/widgets/upload_progress_list.dart`

### Nouveaux fichiers (core helpers — 2)
- `lib/core/utils/byte_format.dart`
- `lib/core/utils/storage_error_mapper.dart`

### Nouveaux fichiers (tests Flutter — 15)
- `test/unit/document_test.dart`
- `test/unit/document_category_test.dart`
- `test/unit/documents_quota_test.dart`
- `test/unit/byte_format_test.dart`
- `test/unit/documents_repository_test.dart`
- `test/unit/upload_documents_controller_test.dart`
- `test/unit/delete_document_controller_test.dart`
- `test/unit/update_category_controller_test.dart`
- `test/unit/storage_error_mapper_test.dart`
- `test/widget/documents_section_test.dart`
- `test/widget/document_list_tile_test.dart`
- `test/widget/upload_documents_drop_zone_test.dart`
- `test/widget/edit_category_dialog_test.dart`
- `test/widget/delete_document_dialog_test.dart`
- `test/widget/upload_progress_list_test.dart`

### Fichiers modifiés (Flutter — 3)
- `lib/core/utils/postgrest_error_mapper.dart` (extension cf. §7.1)
- `lib/features/leases/presentation/lease_detail_page.dart` (ajout `DocumentsSection`)
- `pubspec.yaml` (+ `file_picker`, + `mime`)

### Fichiers modifiés (state post-merge — 5)
- `docs/state/INDEX.md`, `docs/state/SCHEMA.md`, `docs/state/FUNCTIONS.md`, `docs/state/FEATURES.md`, `docs/state/DEPENDENCIES.md` (par `state-keeper`)

**Total estimé** : ~38 fichiers nouveaux + ~3 modifiés (hors `state-keeper`).

---

## 17. Estimation

**Priorité** : P0 (MVP)

**Effort total** : M-L (2-3 jours, +0,5j si drag&drop natif Web s'avère complexe)

Décomposition :
- Migration SQL + RPC + RLS tests : 0,5 jour
- Dépendances + domain Flutter (modèles, enums, sealed states) : 0,5 jour
- Repository + storage logic + mappers : 0,5 jour
- Controllers + providers + invalidation patterns : 0,5 jour
- UI widgets (8 widgets, dont drop zone + dialogs) : 0,75 jour
- Tests Flutter (15 fichiers) + QA staging : 0,75 jour
- Review + state refresh : 0,25 jour

---

## 18. Definition of Done

- [ ] Migration `documents` appliquée (public + dev), RLS activée, 4 triggers posés (tr_00, tr_00b, tr_01, tr_01b, tr_02)
- [ ] RPC `soft_delete_document` (public + dev) testée pour les deux branches (legal_hold true / false)
- [ ] Bucket `documents` provisionné avec MIME whitelist + 10 MB limit + 3 policies Storage
- [ ] Tests SQL RLS passent (19 tests documents + 7 tests storage = 26 cumulés)
- [ ] Upload mono-fichier PDF + image (JPG, PNG, WEBP) validés bout-en-bout en staging
- [ ] Multi-upload 5 fichiers en une opération fonctionnel
- [ ] Drag & drop Web validé OU reporté P1 avec justification (cf. §11 Q3)
- [ ] Erreur taille > 10 MB rejetée avant tout appel réseau
- [ ] Erreur MIME hors whitelist rejetée côté client + côté Storage
- [ ] Quota warning à 100 MB s'affiche correctement
- [ ] Soft-delete document `autre` : disparaît de liste + fichier supprimé de Storage
- [ ] Soft-delete document `bail_signe` : disparaît de liste + fichier conservé en Storage + SnackBar mention legal_hold
- [ ] Modification de catégorie fonctionnelle (et persistante)
- [ ] Signed URL 5 min fonctionne pour download nouvel onglet
- [ ] Empty state cohérent PR #18 (icon primary + wording positif)
- [ ] Tests Flutter passent : 15 fichiers, ~50 tests
- [ ] `flutter analyze` clean, `dart format` appliqué
- [ ] `code-reviewer` ✅, `security-auditor` ✅ (focus orphan handling + legal_hold + cross-user)
- [ ] Déployé Firebase Hosting staging
