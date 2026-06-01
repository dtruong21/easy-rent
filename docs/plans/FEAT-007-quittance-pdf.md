# Plan — [FEAT-007] Générer une quittance PDF de loyer

> Source story : [`docs/backlog/007-quittance-pdf.md`](../backlog/007-quittance-pdf.md)
> Pattern de référence : [`docs/plans/FEAT-006-payment-record.md`](FEAT-006-payment-record.md)

## 1. Vue d'ensemble

**Objectif** : générer un PDF légalement conforme (loi 6 juillet 1989 art. 21) pour une période de location, sur la base des `payments` actifs de cette période. Choix automatique quittance vs reçu selon montant total vs `lease.rent_amount_cents + lease.charges_amount_cents`. Persister dans `public.receipts` + Supabase Storage `receipts/`. Première Edge Function du projet.

**Dépendances** :
- FEAT-001 (auth, `landlord_id = auth.uid()`)
- FEAT-002 (pattern RLS, RPC SECURITY DEFINER, soft-delete)
- FEAT-005 (lease pivot : `rent_amount_cents`, `charges_amount_cents`)
- FEAT-006 (`payments` : source des montants)
- `landlords.full_name` + `landlords.address` (FEAT-002, optionnels) — exigés non-NULL pour générer

**Débloque** : FEAT-008 (envoi email Resend lira `receipts.pdf_path` et générera URL signée).

**Scope** :
- Table `public.receipts` + `dev.receipts` + RLS + triggers
- Bucket Supabase Storage `receipts/` (idempotent via migration) + policies storage
- Edge Function Deno `generate-receipt` (pdf-lib)
- Module Flutter `lib/features/receipts/`
- Page `/profile` (sous-feature) pour saisir `landlord.full_name` + `landlord.address` + `phone`
- Boutons "Générer quittance" sur `PaymentListTile` et `LeaseDetailPage`
- Page `/leases/:id/receipts` (liste des quittances émises pour ce bail)

**Hors scope** :
- Envoi email (FEAT-008)
- Signature électronique eIDAS, tampon
- Numérotation séquentielle annuelle "2026-001" (UUID + `generated_at` suffisent en MVP)
- Régularisation annuelle de charges (P2)
- Multi-langue (FR uniquement)
- Page `/documents` globale (FEAT-009)

---

## 2. Modèle de données — `receipts` (public + dev)

### 2.1 Colonnes

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PK, DEFAULT `gen_random_uuid()` |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` ON DELETE RESTRICT — dénormalisé pour RLS |
| `lease_id` | `uuid` | NOT NULL, FK → `leases(id)` ON DELETE RESTRICT |
| `payment_ids` | `uuid[]` | NOT NULL, CHECK `array_length(payment_ids, 1) >= 1` — paiements inclus |
| `period_start` | `date` | NOT NULL, CHECK BETWEEN `'1900-01-01'` AND `'2100-12-31'` |
| `period_end` | `date` | NOT NULL, CHECK `period_end > period_start` AND BETWEEN bornes |
| `rent_cents` | `integer` | NOT NULL CHECK `> 0` — somme `rent_amount_cents` paiements inclus |
| `charges_cents` | `integer` | NOT NULL DEFAULT 0 CHECK `>= 0` |
| `total_cents` | `integer` | NOT NULL, CHECK `total_cents = rent_cents + charges_cents` |
| `document_type` | `text` | NOT NULL, CHECK IN (`'quittance'`, `'recu'`) |
| `pdf_path` | `text` | NOT NULL — chemin Storage `receipts/<landlord_id>/<receipt_id>.pdf` (pas l'URL ; URL signée à la demande) |
| `generated_at` | `timestamptz` | NOT NULL DEFAULT `now()` |
| `generated_by` | `uuid` | NOT NULL DEFAULT `auth.uid()` — auditabilité, FK `auth.users(id)` ON DELETE NO ACTION |
| `is_voided` | `boolean` | NOT NULL DEFAULT `false` |
| `voided_at` | `timestamptz` | NULL, CHECK `(is_voided = false AND voided_at IS NULL) OR (is_voided = true AND voided_at IS NOT NULL)` |
| `voided_reason` | `text` | NULL, CHECK `char_length(voided_reason) <= 500` |
| `is_stale` | `boolean` | NOT NULL DEFAULT `false` — recalculé via trigger sur soft-delete d'un payment lié |
| `created_at` | `timestamptz` | NOT NULL DEFAULT `now()` |

**Pas de `updated_at`** : document immuable hors flags `is_voided` / `is_stale` (preuve légale).
**Pas de `deleted_at`** : rétention légale 5 ans, jamais de suppression. `is_voided` remplace.

### 2.2 Indexes

```
idx_public_receipts_landlord_id           (landlord_id)              -- RLS filtrage
idx_public_receipts_lease_id              (lease_id)                 -- listing par bail
idx_public_receipts_period_start_desc     (lease_id, period_start DESC)
idx_public_receipts_payment_ids_gin       USING GIN (payment_ids)    -- recherche par paiement (trigger is_stale)
```
Mirroirs `idx_dev_receipts_*` sur `dev.receipts`.

### 2.3 Triggers

- **`tr_00_assert_receipt_lease_ownership`** BEFORE INSERT (pas d'UPDATE — doc immuable)
  - Fonction `public.assert_receipt_lease_ownership()` SECURITY DEFINER + `SET search_path = public`
  - Valide : (a) `lease_id` existe dans `public.leases` (même soft-deleted toléré : régularisation post-clôture), (b) `lease.landlord_id = NEW.landlord_id`
  - ERRCODE 23514 ("Ownership mismatch") en cas d'échec
  - Pattern strictement aligné `assert_payment_lease_ownership()` ([`supabase/migrations/20260531102202_feat006_payments.sql`](../../supabase/migrations/20260531102202_feat006_payments.sql))
  - Miroir `dev.assert_receipt_lease_ownership()`

- **`tr_01_prevent_protected_columns_change_receipts`** BEFORE INSERT OR UPDATE
  - Réutilise `public.prevent_protected_columns_change()` (FEAT-002)
  - Bloque modification directe de `created_at`. Le check `deleted_at` est sans objet (colonne absente) mais la fonction est tolérante (NEW->deleted_at IS NULL ; aucun effet).
  - Le verrou immuabilité des autres champs (`landlord_id`, `lease_id`, `payment_ids`, montants, `pdf_path`, `document_type`) est assuré par **l'absence de policy UPDATE en RLS** (cf. §2.4). Plus simple qu'un trigger custom.

- **Pas de `tr_02_set_updated_at`** (pas de colonne `updated_at`).

- **`tr_03_set_receipt_stale_on_payment_delete`** AFTER UPDATE ON `payments` (déclenché sur le payment, pas sur receipts)
  - Si `OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL` → marquer `receipts.is_stale = true` pour toute receipt dont `payment_ids @> ARRAY[NEW.id]::uuid[]`
  - Fonction `public.recompute_receipt_stale_on_payment_archive()` SECURITY DEFINER + `SET search_path = public`
  - Le flag `app.allow_deleted_at_change` n'est pas requis ici (on n'altère pas `deleted_at`)
  - Bypass RLS volontaire (correction transverse)
  - Miroir `dev.recompute_receipt_stale_on_payment_archive()` sur `dev.payments` / `dev.receipts`
  - **Rationale** : trigger plutôt que computed-on-read pour éviter un OR EXISTS coûteux à chaque SELECT et garantir un `is_stale` fiable dans la liste.

### 2.4 Policies RLS

| Policy | Op | Condition |
|---|---|---|
| `receipts_select_own` | SELECT | `landlord_id = auth.uid()` |
| `receipts_insert_own` | INSERT | WITH CHECK `landlord_id = auth.uid()` |

**Pas de policy UPDATE** : `is_voided` doit passer par une RPC dédiée (cf. §2.5). Aucun champ métier n'est jamais réécrit.
**Pas de policy DELETE** : rétention 5 ans, aucun chemin de suppression.

**Note SELECT** : `is_voided = true` reste visible (preuve d'annulation). Le filtre se fait côté Flutter pour distinguer "actives" vs "voided" si besoin (cf. §6 — la liste `/leases/:id/receipts` les montre toutes avec badge "Annulée").

### 2.5 RPC `void_receipt(p_id uuid, p_reason text)`

Réplique le pattern `soft_delete_*` :
- `SECURITY DEFINER`, `SET search_path = public`
- `UPDATE public.receipts SET is_voided = true, voided_at = now(), voided_reason = p_reason WHERE id = p_id AND landlord_id = auth.uid() AND is_voided = false`
- `RAISE EXCEPTION ERRCODE = 'P0002'` si NOT FOUND (déjà voided ou cross-user)
- `REVOKE ALL FROM PUBLIC; GRANT EXECUTE TO authenticated`
- Miroir `dev.void_receipt(uuid, text)`

**Décision** : pas de `unvoid_receipt` au MVP (un void est définitif côté UX ; en cas d'erreur, on génère un nouveau receipt).

### 2.6 Vérification fin de migration

`SELECT dev.assert_rls_both_schemas('receipts');` (pattern FEAT-006 ligne finale).

---

## 3. Bucket Supabase Storage `receipts/`

### 3.1 Création (idempotent dans la migration)

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('receipts', 'receipts', false)
ON CONFLICT (id) DO NOTHING;
```

Bucket **privé** (`public = false`). Pas d'URL publique — uniquement URLs signées générées à la demande (par l'Edge Function ou un appel `storage.from('receipts').createSignedUrl(path, 300)` côté Flutter).

### 3.2 Structure de chemin

```
receipts/<landlord_id>/<receipt_id>.pdf
```
Une seule racine partagée entre PROD (`public.receipts`) et DEV (`dev.receipts`) — l'isolation se fait via `landlord_id` (auth.uid()). Pas de bucket séparé dev/prod : le `storage` schema est partagé, c'est cohérent avec le pattern multi-env single-database.

### 3.3 Policies Storage

| Policy | Op | Condition |
|---|---|---|
| `receipts_storage_select_own` | SELECT | `bucket_id = 'receipts' AND (storage.foldername(name))[1] = auth.uid()::text` |
| `receipts_storage_insert_own` | INSERT | WITH CHECK `bucket_id = 'receipts' AND (storage.foldername(name))[1] = auth.uid()::text` |

**Pas de UPDATE/DELETE storage** : les PDF sont immuables (rétention 5 ans). Si l'Edge Function échoue après upload, le fichier reste orphelin — toléré au MVP (cron de nettoyage en P2 si volume problématique).

`storage.foldername(name)` retourne un `text[]` ; `[1]` est le premier segment (= landlord_id).

---

## 4. Edge Function `generate-receipt`

### 4.1 Localisation et structure

```
supabase/functions/
├── _shared/
│   ├── cors.ts                  # Headers CORS communs
│   ├── supabase_client.ts       # Helper createClient(req) qui propage le JWT
│   └── money_format.ts          # formatEurosFromCents (locale fr-FR)
└── generate-receipt/
    ├── index.ts                 # Handler Deno.serve
    ├── deps.ts                  # imports pdf-lib, supabase-js, std/http
    ├── pdf_layout.ts            # Construction du PDF (art. 21 loi 1989)
    └── README.md                # Run/deploy doc (optional)
```

**Première Edge Function du projet** : crée aussi `supabase/functions/_shared/` (sera réutilisé en FEAT-008). Met à jour `supabase/config.toml` si besoin (déclarer la function avec `verify_jwt = true` qui est le défaut — explicite pour audit).

### 4.2 Dépendances Deno

| Import | Source | Usage |
|---|---|---|
| `pdf-lib` | `https://esm.sh/pdf-lib@1.17.1` | Génération PDF pur-JS, compatible Deno, contrôle fin layout |
| `@supabase/supabase-js` | `https://esm.sh/@supabase/supabase-js@2.45.0` | Client (JWT propagation pour RLS) + Storage |
| `std/http/server` | `https://deno.land/std@0.224.0/http/server.ts` | Deno.serve fallback (legacy) |

**Pourquoi `pdf-lib` et pas alternative** :
- `puppeteer` : démarrage > 2s, RAM > 200MB, dépasse les limites Edge Functions. Rejeté.
- `pdfkit` : a une vraie API streaming mais l'écosystème Deno est mal supporté ; ESM via `esm.sh` instable.
- `pdfmake` : déclaratif sympa mais bundle 1MB+ via esm.sh, ralentit le cold start.
- `pdf-lib` : pur JS, ESM natif, < 500KB, suffisant pour un layout texte/tableau simple.

**Risque dep transient** : `pdf-lib` ne fournit pas de polices par défaut côté serveur (les `StandardFonts.Helvetica` couvrent ASCII de base mais pas les caractères accentués français au-delà de WinAnsi). Solution : utiliser `StandardFonts.Helvetica` (couvre Latin-1, donc é/è/à/ç OK), tester explicitement les caractères "œ", "€", "É" — embarquer une police TTF custom (ex: Open Sans) en `.ttf` dans le repo si problème. À vérifier en début de dev.

### 4.3 Contrat HTTP

**POST `/functions/v1/generate-receipt`**

Headers :
- `Authorization: Bearer <JWT>` (obligatoire — `verify_jwt = true`)
- `Content-Type: application/json`

Body (deux modes acceptés) :
```json
{ "lease_id": "<uuid>", "period_start": "2026-05-01", "period_end": "2026-05-31" }
```
ou
```json
{ "payment_ids": ["<uuid>", "<uuid>"] }
```

Mode 1 (lease+période) : la function liste tous les `payments` actifs (`deleted_at IS NULL`) qui chevauchent strictement la période demandée → somme.
Mode 2 (explicite) : utilise exactement les paiements fournis. Plus déterministe ; recommandé depuis l'UI. Le mode 1 est utile pour `/leases/:id/receipts` qui propose "Générer pour mai 2026".

**Validation** : si les deux modes sont fournis simultanément → 400. Si aucun → 400. **Décision** : implémenter le mode 2 en priorité (déclenché depuis `PaymentListTile`). Le mode 1 peut être supporté par une couche de calcul côté Edge Function qui dérive les `payment_ids` puis appelle le même code → unification.

Response 200 :
```json
{
  "receipt_id": "<uuid>",
  "document_type": "quittance" | "recu",
  "total_cents": 100000,
  "pdf_url": "https://<project>.supabase.co/storage/v1/object/sign/receipts/...",
  "pdf_url_expires_at": "2026-05-31T12:05:00Z"
}
```

Codes d'erreur :
- `401` : pas de JWT / invalide (géré par Supabase)
- `400` : body invalide, modes mixés, dates invalides
- `403` : payments ou lease n'appartenant pas au landlord (ownership)
- `404` : lease introuvable
- `422` :
  - `landlord.full_name` ou `landlord.address` NULL → message "Complétez votre profil bailleur"
  - aucun paiement actif pour la période
  - paiements sur des baux différents
  - dates incohérentes (period_end <= period_start)
- `500` : échec génération PDF ou upload Storage

### 4.4 Pipeline d'exécution

1. **Auth** : créer un Supabase client avec le JWT du header (`createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } })`). Toutes les requêtes héritent du JWT → RLS s'applique → ownership gratuit.
2. **Charge `auth.uid()`** depuis le JWT (côté client supabase ou via `auth.getUser()`).
3. **Charge `landlord`** : `SELECT id, full_name, address FROM landlords WHERE id = auth.uid()` (RLS auto).
4. **Vérifie profil complet** : `full_name` et `address` non NULL et non vides → sinon return 422.
5. **Charge paiements** :
   - Mode 2 : `.from('payments').select('*').in('id', payment_ids).is('deleted_at', null)` → RLS filtre ownership ; vérifier que le count retourné = len(payment_ids) sinon 403 (cross-user).
   - Mode 1 : `.from('payments').select('id').eq('lease_id', lease_id).gte('period_start', period_start).lte('period_end', period_end).is('deleted_at', null)` → puis appel mode 2 avec les ids retournés.
6. **Valide cohérence** : tous les paiements partagent le même `lease_id` ; les périodes des paiements sont incluses dans la période demandée (sinon 422).
7. **Charge lease + property + tenant + landlord** (jointures via `.select('*, leases(*, properties(*), tenants(*))')` — RLS auto). Bail soft-deleted toléré (régularisation rétroactive autorisée).
8. **Calcule totaux** : `rent_cents = SUM(payments.rent_amount_cents)`, `charges_cents = SUM(payments.charges_amount_cents)`, `total_cents = rent_cents + charges_cents`.
9. **Détermine `document_type`** :
   - Référence dûe = `lease.rent_amount_cents + lease.charges_amount_cents`
   - Si `total_cents >= référence dûe` → `'quittance'`
   - Sinon → `'recu'`
10. **Génère PDF** (cf. §5) via `pdf_layout.ts`. Retourne un `Uint8Array`.
11. **Upload Storage** : `storage.from('receipts').upload('<landlord_id>/<new_uuid>.pdf', bytes, { contentType: 'application/pdf', upsert: false })`. En cas d'erreur → 500.
12. **INSERT `public.receipts`** avec `id = <new_uuid>`, `pdf_path = '<landlord_id>/<new_uuid>.pdf'`, payment_ids, rent_cents, charges_cents, total_cents, document_type, period_start, period_end (déduits des paiements : min/max). RLS auto.
13. **Crée signed URL** : `storage.from('receipts').createSignedUrl(pdf_path, 300)` (5 min) → retourne au client.
14. **Retourne 200 JSON** avec receipt_id, document_type, total_cents, pdf_url.

### 4.5 Idempotence

**Décision** : pas d'idempotence forte côté serveur. Si l'utilisateur re-clique "Générer", une nouvelle receipt est créée (UUID différent, nouveau fichier). La story (AC "Idempotence") autorise explicitement ce comportement et propose un dialog UI "Une quittance existe déjà — télécharger l'ancienne OU en créer une nouvelle ?" (cf. §6.4).

**Risque** : un double-clic rapide crée deux PDFs identiques. Mitigation côté UI : `payment_form_controller` pattern → disable button pendant le `Future.wait`.

### 4.6 Erreurs de partial-failure

Ordre choisi :
1. **PDF généré → upload Storage OK → INSERT DB échoue** : fichier orphelin dans Storage. Toléré au MVP (rare ; nettoyage manuel possible). Loguer `[orphan-pdf] landlord=<x> path=<y>` pour grep.
2. **PDF généré → upload Storage échoue** : pas d'INSERT DB. Cohérent.
3. **INSERT DB avant upload Storage** : option rejetée (si upload échoue, on a un row sans fichier — pire que l'inverse).

---

## 5. Mentions PDF (loi 1989 art. 21) — squelette de layout

Format A4 portrait (210 × 297 mm). Marges 20 mm. Police `Helvetica` (StandardFonts).

```
┌────────────────────────────────────────────────────────┐
│ <landlord.full_name>                       <ville>, le │
│ <landlord.address>                  <date generated>   │  ← Ligne 1
│                                                        │
│                                                        │
│         QUITTANCE DE LOYER  /  REÇU DE PAIEMENT        │  ← Titre centré, 18pt bold
│             (Loyer de <mois> <année>)                  │  ← Sous-titre 12pt
│                                                        │
│ Locataire :                                            │
│   <tenant.first_name> <tenant.last_name>               │
│                                                        │
│ Logement :                                             │
│   <property.address>                                   │
│                                                        │
│ Période concernée :                                    │
│   du <period_start DD/MM/YYYY> au <period_end DD/MM/YYYY> │
│                                                        │
│ Détail du paiement :                                   │
│   Loyer hors charges ................. 1 234,56 €      │
│   Charges ............................   123,45 €      │
│   ─────────────────────────────────────────────        │
│   Total reçu .......................... 1 357,01 €     │
│                                                        │
│ <SI document_type = 'recu'>                            │
│ ⚠ Ce reçu ne libère pas le locataire du solde dû      │
│   pour la période concernée.                           │
│ </SI>                                                  │
│                                                        │
│ <SI document_type = 'quittance'>                       │
│ Le bailleur déclare avoir reçu du locataire la somme   │
│ indiquée, ce qui le libère pour la période concernée.  │
│ </SI>                                                  │
│                                                        │
│ Fait à <landlord.address[ville extraite]>, le <date>.  │
│                                                        │
│                                       Signature        │
│                                       <full_name>      │
│                                                        │
│ ──────────────────────────────────────────────────────  │
│ Document généré par EasyRent — Réf : <receipt_id court> │  ← Footer 8pt gris
└────────────────────────────────────────────────────────┘
```

**Spécifications précises** :
- Tous les montants : `formatEurosFromCents(cents)` → `"1 234,56 €"` (espace insécable U+00A0, virgule décimale)
- Toutes les dates : `formatDateFr(d)` → `"31/05/2026"` (DD/MM/YYYY)
- Mois affiché : `"mai 2026"` (locale FR via une LUT statique côté Deno : `['janvier','février',...,'décembre']` indexée par `period_start.getMonth()`)
- Ville pour "Fait à" : à défaut d'un champ dédié, parser le dernier segment de `landlord.address` (heuristique faible) OU laisser un placeholder `___________` (recommandation MVP : afficher l'adresse complète sur la ligne "Fait à" pour rester juridiquement valide même si non élégant)

**Bornes de validation amont** : si une mention obligatoire ne peut pas être produite (ex: `tenant.first_name` vide), la function renvoie 422 avec un message explicite. Ne **jamais** générer un PDF incomplet.

---

## 6. Structure Flutter — `lib/features/receipts/`

Pattern strictement aligné [`lib/features/payments/`](../../lib/features/payments/).

```
lib/features/receipts/
├── domain/
│   ├── receipt.dart                       # freezed + json_serializable
│   ├── receipt.freezed.dart               # GÉNÉRÉ
│   ├── receipt.g.dart                     # GÉNÉRÉ
│   ├── document_type.dart                 # enum: quittance | recu (fromSql / sqlValue / label)
│   ├── generate_receipt_request.dart      # freezed : sealed {ByPayments(List<String>) | ByPeriod(leaseId, start, end)}
│   ├── receipt_generation_state.dart      # freezed sealed : idle | submitting | success(Receipt, pdfUrl) | error
│   └── *.freezed.dart                     # GÉNÉRÉS
├── data/
│   └── receipts_repository.dart           # interface + SupabaseReceiptsRepository + provider Riverpod
├── application/
│   ├── lease_receipts_provider.dart       # AsyncNotifier.family<List<Receipt>, String leaseId>
│   ├── generate_receipt_controller.dart   # StateNotifier — invoke Edge Function, gère UI state
│   └── receipt_pdf_url_provider.dart      # FutureProvider.family<String, String receiptId> — signedUrl à la demande
└── presentation/
    ├── lease_receipts_page.dart           # Page /leases/:id/receipts (liste)
    └── widgets/
        ├── receipt_list_section.dart      # (optionnel) Card "Quittances" dans LeaseDetailPage — résumé 3 dernières + lien "Voir toutes"
        ├── receipt_list_tile.dart         # période + type (badge quittance/reçu) + montant + actions (télécharger, voir, void)
        ├── generate_receipt_button.dart   # Widget réutilisable bouton → invoke Edge Function → ouvre dialog
        ├── receipt_preview_dialog.dart    # AlertDialog avec icône + résumé + actions [Télécharger] [Fermer]
        ├── receipt_stale_badge.dart       # Badge orange "Données modifiées" si is_stale
        └── receipt_voided_badge.dart      # Badge gris "Annulée" si is_voided
```

### 6.1 Repository — méthodes

```dart
abstract interface class ReceiptsRepository {
  Future<List<Receipt>> listForLease(String leaseId);
  Future<Receipt> getById(String id);
  Future<({Receipt receipt, String pdfUrl})> generate(GenerateReceiptRequest req);
  Future<String> createSignedUrl(String receiptId);  // appelle storage.from('receipts').createSignedUrl
  Future<void> voidReceipt(String id, String reason); // RPC void_receipt
}
```

**Implémentation `generate`** : `Db.functions.invoke('generate-receipt', body: req.toJson())` puis parse réponse. **Pas** d'INSERT direct côté Flutter (toute la logique est serveur).

### 6.2 Providers

| Provider | Type | Usage |
|---|---|---|
| `lease_receipts_provider(leaseId)` | `AsyncNotifierProvider.family<.., List<Receipt>, String>` | Liste filtrée par bail, ordre `period_start DESC` |
| `generate_receipt_controller_provider` | `StateNotifierProvider.autoDispose<.., ReceiptGenerationState>` | Submit + invalidate `lease_receipts_provider(leaseId)` au success |
| `receipt_pdf_url_provider(receiptId)` | `FutureProvider.family.autoDispose<String, String>` | Signed URL fresh à chaque ouverture |

Pattern d'invalidation : success → `ref.invalidate(leaseReceiptsProvider(leaseId))` (cf. [`payment_form_controller.dart`](../../lib/features/payments/application/payment_form_controller.dart)).

### 6.3 Routes go_router

Ajouter dans [`lib/core/router/app_router.dart`](../../lib/core/router/app_router.dart) après les routes payments :

```
/leases/:id/receipts        → LeaseReceiptsPage(leaseId: ...)
/profile                    → ProfilePage (cf. §7)
```

**Pas de route détail `/leases/:id/receipts/:rid`** : un tap ouvre le PDF dans un nouvel onglet via signed URL (cf. `printing.openSharePdf` ou `url_launcher` — préférer `launchUrl(pdfUrl, mode: LaunchMode.externalApplication)`).

**Pas de route `/receipts` globale** au MVP. Reportée à FEAT-009/010.

### 6.4 Boutons "Générer quittance" — points d'entrée

1. **Sur `PaymentListTile`** ([`lib/features/payments/presentation/widgets/payment_list_tile.dart`](../../lib/features/payments/presentation/widgets/payment_list_tile.dart)) : ajouter une action menu "Générer quittance pour cette période". Récupère `lease_id` + `period_start`/`period_end` du paiement → invoke `generate({by_period:...})`.

2. **Sur `LeaseDetailPage`** : nouveau bouton "Générer quittance" qui ouvre un sélecteur "Mois/année" (DropdownButton année + DropdownButton mois) → invoke `generate({by_period:...})`.

3. **Sur `LeaseReceiptsPage`** (nouvelle) : bouton "+" → même sélecteur.

**Confirmation si receipt déjà existante** : `generate_receipt_controller` lit d'abord `lease_receipts_provider(leaseId)` ; si une receipt non-voided existe déjà pour cette période, affiche un dialog "Une quittance existe déjà pour mai 2026. [Télécharger l'existante] [Générer une nouvelle]". Pas de blocage dur — le bailleur peut légitimement régénérer (correction d'erreur, ajout d'un paiement tardif).

### 6.5 Helpers utilisés

| Helper | Status |
|---|---|
| `MoneyFormat.formatEurosFromCents` | Réutiliser tel quel ([`lib/core/utils/money_format.dart`](../../lib/core/utils/money_format.dart)) |
| `mapPostgrestError` | Réutiliser ([`lib/core/utils/postgrest_error_mapper.dart`](../../lib/core/utils/postgrest_error_mapper.dart)) |
| **Nouveau** : `mapEdgeFunctionError(FunctionException)` | À créer dans `lib/core/utils/edge_function_error_mapper.dart` — mappe codes HTTP 401/403/422/500 → messages FR |
| `formatDateFr(DateTime)` | À ajouter à `date_helpers.dart` si pas déjà présent (vérifier) |

---

## 7. Sous-feature : page `/profile`

### 7.1 Objectif

Permettre au bailleur de saisir `landlord.full_name`, `landlord.address`, `landlord.phone` (ce dernier facultatif mais cohérent à exposer). Sans ces champs, FEAT-007 est bloqué (cf. §4.4 étape 4).

### 7.2 Structure

```
lib/features/profile/
├── domain/
│   ├── landlord_profile.dart              # freezed mapping de landlords (full_name, phone, address)
│   ├── landlord_profile.freezed.dart      # GÉNÉRÉ
│   ├── landlord_profile.g.dart            # GÉNÉRÉ
│   └── profile_form_state.dart            # freezed sealed : idle | submitting | success | error
├── data/
│   └── profile_repository.dart            # SELECT/UPDATE landlords (RLS : seulement self)
├── application/
│   ├── landlord_profile_provider.dart     # AsyncNotifierProvider<.., LandlordProfile>
│   └── profile_form_controller.dart       # StateNotifier
└── presentation/
    ├── profile_page.dart                  # ProfilePage (form unique)
    └── widgets/
        └── profile_form.dart              # Champs : nom complet, téléphone, adresse
```

### 7.3 Repository et provider

- `getCurrentProfile()` : `Db.from('landlords').select('id, full_name, phone, address').eq('id', currentUserId).maybeSingle()`. RLS auto.
- `updateProfile({fullName, phone, address})` : `Db.from('landlords').update({...}).eq('id', currentUserId)`. RLS auto. Trigger `tr_02_set_updated_at_landlords` met à jour `updated_at` automatiquement.

### 7.4 Validations

| Champ | Règle |
|---|---|
| `full_name` | NOT NULL, length 2..200 |
| `address` | NOT NULL, length 5..500 |
| `phone` | NULL ou regex E.164 souple (`^[+0-9 .]{6,20}$`) |

À implémenter dans `lib/core/utils/profile_form_validators.dart` (nouveau, pattern strictement aligné `tenant_form_validators.dart`).

### 7.5 Accès UI

- Lien dans le drawer (à créer si pas existant) OU AppBar trailing icon `Icons.account_circle` sur toutes les pages auth. **Décision** : ajouter un `IconButton` à `LeaseDetailPage` AppBar pour MVP (drawer global = scope FEAT-010).
- Auto-redirect : si `full_name` ou `address` NULL au moment de cliquer "Générer quittance" → SnackBar "Complétez votre profil" + bouton "Aller au profil" → `/profile`.

### 7.6 Tests

- Widget : `profile_form_test.dart` (validation, submit OK, submit erreur)
- Validator : `profile_form_validators_test.dart`

---

## 8. Décisions tranchées

| Sujet | Décision |
|---|---|
| Numérotation | UUID + `generated_at`. Pas de séquence "2026-001" au MVP. |
| Régularisation de charges | Hors scope FEAT-007. P2. |
| Bail clôturé | Génération rétroactive autorisée (cas régularisation post-clôture fréquent). |
| Soft-delete d'un payment lié | `is_stale = true` via trigger `tr_03_set_receipt_stale_on_payment_delete`. PDF conservé. |
| Annulation receipt | RPC `void_receipt` (flag `is_voided`). Jamais de DELETE. |
| Idempotence | Côté UI uniquement (dialog "déjà existante"). Le serveur génère toujours un nouveau receipt si appelé. |
| Storage path | `receipts/<landlord_id>/<receipt_id>.pdf` (bucket privé) |
| Expiration signed URL | 5 min (300s). À chaque téléchargement → nouveau signed URL via `receipt_pdf_url_provider`. |
| Génération | Edge Function Deno (jamais Flutter) — décision produit |
| Lib PDF | `pdf-lib` ESM via esm.sh ; police `Helvetica` StandardFonts |
| Verify JWT | `true` (défaut Supabase) |
| Profil incomplet | Erreur 422 explicite + page `/profile` dans scope |

---

## 9. Plan de tests

### 9.1 Tests Edge Function Deno (`supabase/functions/generate-receipt/tests/`)

Framework : `deno test --allow-net --allow-env`. Fichiers :
- `pdf_layout_test.ts` : génère un PDF avec données mock, parse les bytes (via `pdf-parse` ESM ou regex sur le stream texte) et vérifie présence des mentions obligatoires (`tenant.full_name`, `property.address`, montants formatés, mention solde si recu).
- `compute_document_type_test.ts` : table de vérité quittance vs reçu (paiement exact, > loyer, < loyer, multi-paiements sommés, charges=0).
- `auth_test.ts` : appel sans JWT → 401. Cross-user (payment_ids d'un autre landlord) → 403.
- `profile_validation_test.ts` : landlord sans full_name → 422 ; sans address → 422.
- `period_validation_test.ts` : period_end <= period_start → 400 ; aucun payment trouvé → 422.

Cible : ~15 tests Deno.

### 9.2 Tests SQL RLS (`supabase/tests/rls_receipts.sql`)

Pattern [`rls_payments.sql`](../../supabase/tests/rls_payments.sql). Couverture :
1. User A voit ses receipts (public + dev) — 2 tests
2. User A ne voit PAS celles de User B — 2 tests
3. INSERT direct côté authenticated avec `landlord_id = auth.uid()` réussit — 2 tests
4. INSERT avec `landlord_id` d'un autre user → 42501 — 2 tests
5. Trigger `assert_receipt_lease_ownership` : INSERT avec lease d'un autre → 23514 — 2 tests
6. CHECK `total_cents = rent_cents + charges_cents` refusé — 1 test
7. CHECK `document_type` non-enum refusé — 1 test
8. CHECK `array_length(payment_ids,1) >= 1` refusé — 1 test
9. UPDATE bloqué (pas de policy UPDATE) — 2 tests
10. DELETE bloqué (pas de policy DELETE) — 2 tests
11. RPC `void_receipt` cross-user → NOT FOUND — 2 tests
12. Trigger `tr_03_set_receipt_stale_on_payment_delete` : soft-delete payment lié → `is_stale = true` — 2 tests
13. RLS activée sur les deux schémas — 1 test (`assert_rls_both_schemas('receipts')`)

Cible : ~24 tests.

### 9.3 Tests Storage RLS (`supabase/tests/storage_receipts.sql`)

- INSERT objet dans `receipts/<self>/...` autorisé — 1 test
- INSERT dans `receipts/<other>/...` refusé — 1 test
- SELECT objet `receipts/<other>/...` → 0 lignes — 1 test
- Hard-delete refusé (pas de policy DELETE) — 1 test

Cible : 4 tests.

### 9.4 Tests Flutter (`test/unit/`, `test/widget/`)

- `receipt_test.dart` : freezed + JSON roundtrip
- `document_type_test.dart` : fromSql / sqlValue / label
- `receipts_repository_test.dart` : mocks `Db.functions.invoke` ; succès, 422, 403, 500
- `generate_receipt_controller_test.dart` : transitions idle → submitting → success / error
- `lease_receipts_page_test.dart` : empty, loading, populated, item avec `is_stale`, item avec `is_voided`
- `generate_receipt_button_test.dart` : disabled si profil incomplet ; clic → dialog si déjà existante
- `receipt_preview_dialog_test.dart` : affichage, action "Télécharger"
- `profile_page_test.dart` + `profile_form_test.dart` : validation + submit

Cible : ~12 fichiers de tests Flutter.

### 9.5 Tests d'intégration manuelle (QA)

- Génération nominale → PDF s'ouvre, mentions présentes
- Profil incomplet → blocage avec message clair
- Paiement partiel → recu avec mention solde
- Paiement multiple sommé → quittance unique avec total correct
- Soft-delete payment → receipt en liste avec badge "Données modifiées"
- Void receipt → badge "Annulée" mais PDF toujours téléchargeable
- Cross-user (créer 2 comptes) → User B ne voit rien

---

## 10. Plan de migration

**Nom** : `supabase/migrations/<timestamp>_feat007_receipts.sql` (timestamp à figer par `supabase-dev`).

**Structure** (sections, ordre) :
1. `BEGIN;`
2. Section 1 — Fonctions `public.assert_receipt_lease_ownership()` + `dev.assert_receipt_lease_ownership()`
3. Section 2 — Fonctions `public.recompute_receipt_stale_on_payment_archive()` + dev équivalente
4. Section 3 — Table `public.receipts` + index + RLS + policies + triggers tr_00, tr_01 (pas de tr_02)
5. Section 4 — Table `dev.receipts` (miroir) + index + RLS + policies + triggers
6. Section 5 — Trigger `tr_03_set_receipt_stale_on_payment_archive` attaché à `public.payments` + `dev.payments`
7. Section 6 — RPC `public.void_receipt(uuid, text)` + `dev.void_receipt(uuid, text)` (REVOKE/GRANT)
8. Section 7 — Bucket Storage : `INSERT INTO storage.buckets (...) ON CONFLICT DO NOTHING;`
9. Section 8 — Policies Storage (`receipts_storage_select_own`, `receipts_storage_insert_own`)
10. Section 9 — `SELECT dev.assert_rls_both_schemas('receipts');`
11. `COMMIT;`

**Convention multi-env** : appliquer aux deux schémas dans la même migration ([`docs/ENVIRONMENTS.md`](../ENVIRONMENTS.md)).

**Pas de migration séparée pour le bucket** : intégrer directement (cohérent avec FEAT-005 leçon).

---

## 11. Découpage en commits suggéré

1. `feat(receipts): migration + bucket storage + RLS + triggers` — SQL pur, ~600 lignes
2. `feat(profile): page /profile (full_name, address, phone)` — Flutter, ~10 fichiers
3. `feat(receipts): edge function generate-receipt (pdf-lib + storage)` — Deno, ~5 fichiers + import_map
4. `feat(receipts): domain + repository + providers Flutter` — ~10 fichiers
5. `feat(receipts): UI lease_receipts_page + generate_receipt_button + preview_dialog` — ~8 fichiers
6. `test(receipts): tests Edge Function Deno + tests RLS + tests widget Flutter` — ~16 fichiers tests
7. `chore(state): refresh state cache post-FEAT-007` — INDEX.md + SCHEMA.md + ROUTES.md + FEATURES.md + FUNCTIONS.md (créer)

**Ordre d'exécution** :
1. Migration (`supabase-dev`)
2. Edge Function (`supabase-dev` — déploiement via CLI ou push GitHub)
3. Page `/profile` (sans la dépendance Edge Function — peut être implémenté en parallèle)
4. Flutter receipts feature
5. Tests
6. Review (`code-reviewer` + `security-auditor`)
7. State refresh

---

## 12. Risques et questions critiques restantes

### Risques majeurs

1. **Première Edge Function du projet — risque d'amorçage** : pas de pipeline CI/CD pour les fonctions Deno aujourd'hui. Vérifier que `supabase functions deploy generate-receipt` fonctionne en local + staging + qu'un `verify_jwt = true` est bien posé dans `supabase/config.toml`. Risque mitigé : prévoir 0.5 jour de setup infra (config.toml, secrets `SUPABASE_URL` / `SUPABASE_ANON_KEY` accessibles via `Deno.env`).
2. **Police PDF et caractères français** : `StandardFonts.Helvetica` de pdf-lib utilise WinAnsiEncoding qui supporte Latin-1 (é, è, à, ç, €) mais PAS le "œ" (U+0153) ni les guillemets typographiques français « ». Risque : un bailleur nommé "Lhœur" génère un PDF tronqué. Mitigation : embarquer Open Sans TTF (binaire ~150KB) dans `supabase/functions/_shared/fonts/` et utiliser `pdfDoc.embedFont(fontBytes)`. À tester en début de dev — si OK avec WinAnsi, garder simple ; sinon embarquer la police.
3. **Stabilité de `esm.sh` pour pdf-lib** : esm.sh fait du caching CDN mais a connu des outages ponctuels (Nov 2024). Risque cold-start Edge Function. Mitigation : pin la version exacte (`pdf-lib@1.17.1`), envisager `deno_modules` cache local en CI. Pas bloquant pour MVP.
4. **Validation légale du PDF** : aucun avocat n'a relu le layout. La loi 1989 art. 21 énumère des champs mais pas un format précis. Recommandation : faire valider par un juriste avant prod (hors scope dev mais à flagger au product-owner). Mention "ne libère pas le locataire du solde dû" est textuelle obligatoire (à recopier mot pour mot).
5. **Horodatage légal** : `generated_at = now()` n'est pas un horodatage qualifié eIDAS. Pour MVP suffisant (les quittances classiques ne sont pas horodatées en France), mais à documenter dans `/privacy` que le document n'a pas valeur de preuve renforcée.
6. **Signature numérique** : aucune. Le PDF n'a pas de signature électronique. Acceptable légalement pour une quittance (jurisprudence : quittance papier signée à la main acceptée ; PDF non signé reconnu comme commencement de preuve). À documenter.
7. **Confidentialité bucket Storage** : `receipts` bucket privé OK, mais une fuite de signed URL (5 min) reste un risque. Mitigation : pas de partage de URL par défaut côté Flutter ; téléchargement direct via `launchUrl(..., mode: externalApplication)` qui ne laisse pas la URL dans l'historique navigateur.
8. **Trigger `tr_03_set_receipt_stale_on_payment_archive` coûteux** : un UPDATE sur `payments` (soft-delete) déclenche un UPDATE sur `receipts` filtré par `payment_ids @> ARRAY[id]`. L'index GIN sur `payment_ids` rend ça acceptable. Vérifier avec EXPLAIN à 10k receipts.
9. **`pdf` + `printing` packages Flutter inutilisés** : ils sont déclarés dans pubspec (cf. [`DEPENDENCIES.md`](../state/DEPENDENCIES.md) ligne 20-21) mais FEAT-007 ne les utilise pas (génération côté serveur). À retirer en cleanup commit après merge, ou conserver pour un futur fallback offline (P2).

### Questions critiques restantes (à confirmer auprès du product-owner)

1. **Visibilité des receipts `is_voided`** : la liste `/leases/:id/receipts` les affiche-t-elle ? **Recommandation** : OUI avec badge "Annulée" pour audit. À confirmer.
2. **Reason obligatoire au void** : la RPC `void_receipt` exige-t-elle un motif texte non vide ? **Recommandation** : OUI (audit légal), CHECK `char_length(voided_reason) BETWEEN 3 AND 500`.
3. **Période chevauchant deux mois** : un paiement avec `period_start = 2026-05-15`, `period_end = 2026-06-14` est-il acceptable ? FEAT-006 le permet. **Recommandation FEAT-007** : tolérant. La quittance dit "période du 15/05/2026 au 14/06/2026" sans formatage "mois français". À confirmer.
4. **Accès au PDF d'une receipt voided** : un bailleur peut-il télécharger le PDF d'une receipt annulée ? **Recommandation** : OUI (traçabilité). Le badge "Annulée" est purement visuel.
5. **Ville pour "Fait à"** : extraire depuis `landlord.address` (heuristique faible) ou afficher l'adresse complète ? **Recommandation MVP** : afficher l'adresse complète. Ajouter une colonne `landlords.city` en P1 si besoin.
6. **Pdf-lib polices custom** : si Open Sans s'avère nécessaire, où stocker le `.ttf` ? Recommandation : `supabase/functions/_shared/fonts/OpenSans-Regular.ttf` (commit binaire, ~150KB). À valider.

---

## 13. Récapitulatif files créés / modifiés

### Nouveaux fichiers (SQL)
- `supabase/migrations/<timestamp>_feat007_receipts.sql`
- `supabase/tests/rls_receipts.sql`
- `supabase/tests/storage_receipts.sql`

### Nouveaux fichiers (Edge Function)
- `supabase/functions/_shared/cors.ts`
- `supabase/functions/_shared/supabase_client.ts`
- `supabase/functions/_shared/money_format.ts`
- `supabase/functions/_shared/fonts/OpenSans-Regular.ttf` (conditionnel)
- `supabase/functions/generate-receipt/index.ts`
- `supabase/functions/generate-receipt/deps.ts`
- `supabase/functions/generate-receipt/pdf_layout.ts`
- `supabase/functions/generate-receipt/tests/pdf_layout_test.ts`
- `supabase/functions/generate-receipt/tests/compute_document_type_test.ts`
- `supabase/functions/generate-receipt/tests/auth_test.ts`
- `supabase/functions/generate-receipt/tests/profile_validation_test.ts`

### Nouveaux fichiers (Flutter receipts)
- `lib/features/receipts/domain/{receipt,document_type,generate_receipt_request,receipt_generation_state}.dart` (+ générés)
- `lib/features/receipts/data/receipts_repository.dart`
- `lib/features/receipts/application/{lease_receipts_provider,generate_receipt_controller,receipt_pdf_url_provider}.dart`
- `lib/features/receipts/presentation/lease_receipts_page.dart`
- `lib/features/receipts/presentation/widgets/{receipt_list_section,receipt_list_tile,generate_receipt_button,receipt_preview_dialog,receipt_stale_badge,receipt_voided_badge}.dart`
- `lib/core/utils/edge_function_error_mapper.dart`

### Nouveaux fichiers (Flutter profile)
- `lib/features/profile/domain/{landlord_profile,profile_form_state}.dart` (+ générés)
- `lib/features/profile/data/profile_repository.dart`
- `lib/features/profile/application/{landlord_profile_provider,profile_form_controller}.dart`
- `lib/features/profile/presentation/profile_page.dart`
- `lib/features/profile/presentation/widgets/profile_form.dart`
- `lib/core/utils/profile_form_validators.dart`

### Nouveaux fichiers (tests Flutter)
- `test/unit/receipt_test.dart`
- `test/unit/document_type_test.dart`
- `test/unit/receipts_repository_test.dart`
- `test/unit/generate_receipt_controller_test.dart`
- `test/unit/profile_form_validators_test.dart`
- `test/widget/lease_receipts_page_test.dart`
- `test/widget/generate_receipt_button_test.dart`
- `test/widget/receipt_preview_dialog_test.dart`
- `test/widget/profile_page_test.dart`
- `test/widget/profile_form_test.dart`

### Fichiers modifiés
- `lib/core/router/app_router.dart` (2 routes : `/leases/:id/receipts`, `/profile`)
- `lib/features/payments/presentation/widgets/payment_list_tile.dart` (ajouter menu action "Générer quittance")
- `lib/features/leases/presentation/lease_detail_page.dart` (bouton "Générer quittance" + `ReceiptListSection` optionnelle + AppBar icon profil)
- `supabase/config.toml` (déclarer la fonction `generate-receipt`)
- `docs/state/INDEX.md`, `docs/state/SCHEMA.md`, `docs/state/ROUTES.md`, `docs/state/FEATURES.md`, `docs/state/FUNCTIONS.md` (post-merge, par `state-keeper`)

**Total estimé** : ~55-60 fichiers nouveaux + ~6 modifiés.
