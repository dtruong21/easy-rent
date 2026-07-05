# FEAT-009 — Upload & stockage de documents

## User story

En tant que **propriétaire bailleur**, je veux **uploader et consulter des documents (PDF, images) liés à un bail** afin de **centraliser les pièces justificatives importantes (bail signé, état des lieux, attestation assurance) dans EasyRent sans jongler avec des dossiers locaux ou des emails**.

---

## Contexte & motivation

Les features FEAT-005 à FEAT-008 ont livré la gestion des baux, des paiements et des quittances. Il manque la pièce centrale du dossier locatif : le stockage des documents de référence liés à chaque bail.

Aujourd'hui, un bailleur doit rechercher le bail signé dans ses emails, l'attestation d'assurance dans un dossier local et l'état des lieux dans un tiroir. EasyRent doit devenir le point de vérité unique du dossier locatif. Cette feature le permet pour le MVP.

L'infrastructure Storage est déjà partiellement en place : le bucket `receipts/` (FEAT-007) établit le pattern RLS, le chemin `${env}/${userId}/...`, la taille limite à 10 MB et l'URL signée 5 min. FEAT-009 crée un second bucket `documents` isolé, avec une table de métadonnées dédiée.

---

## Personas & scénario principal

**Persona** : David, propriétaire de 3 appartements, gère tout seul sans agence.

**Scénario** : David vient de signer le bail de son locataire. Il ouvre la fiche du bail dans EasyRent, clique sur l'onglet "Documents", puis sur "Ajouter un document". Il sélectionne le PDF du bail signé, choisit la catégorie "Bail signé" et valide. Le document apparaît dans la liste avec son nom, sa catégorie, sa date d'upload et sa taille. Six mois plus tard, il retrouve l'attestation d'assurance en un clic depuis la même fiche.

---

## Décisions à prendre

Les points suivants ne sont pas encore tranchés. Un **défaut raisonné** est proposé pour chacun ; à valider ou infirmer avant implémentation.

### D1 — Validation MIME type : côté client uniquement ou renforcement côté serveur ?

**Situation** : Un fichier `.exe` renommé `.pdf` passerait une validation client basée sur l'extension.

**Options** :
- A) Client Flutter uniquement — vérifie `mime_type` déclaré par le picker (pas d'inspection du contenu)
- B) Client + Storage Policy Supabase — la bucket policy refuse les MIME types non listés (PDF, JPEG, PNG, WEBP) au niveau de l'upload Storage
- C) Client + Edge Function de validation — lit les magic bytes du fichier

**Défaut recommandé** : **Option B** — policy Storage MIME type est simple à poser et sans latence additionnelle. L'option C est over-engineered pour le MVP. L'option A seule est insuffisante (contournable).

### D2 — Quota stockage par landlord : limite hard ou warning soft ?

**Situation** : Sans quota, un bailleur pourrait uploader massivement et épuiser le tier Supabase Storage.

**Options** :
- A) Pas de quota MVP (Supabase free tier = 1 GB total — acceptable pour ~100 bailleurs × 10 docs × 5 MB)
- B) Warning UI à 100 MB par landlord (calculé client-side depuis la somme des `size_bytes` en DB)
- C) Blocage hard à 200 MB par landlord (vérifié dans une Edge Function ou un trigger)

**Défaut recommandé** : **Option B** pour le MVP — warning non-bloquant à 100 MB calculé côté client depuis la somme `size_bytes` en base. Aucune complexité serveur. L'option C est prématurée avant d'avoir des données d'usage réelles.

### D3 — Soft-delete : conserver ou supprimer le fichier en Storage ?

**Situation** : Le bailleur supprime un document de l'interface. Doit-on conserver le binaire en Storage ou le supprimer physiquement ?

**Options** :
- A) Soft-delete uniquement (`deleted_at` en base) — le fichier reste en Storage, invisible dans l'UI mais récupérable par un admin
- B) Soft-delete DB + hard-delete Storage — le fichier est supprimé de Storage immédiatement (RGPD : minimisation des données)
- C) Soft-delete DB, hard-delete Storage différé (cron à J+30) — permet une corbeille de 30 jours

**Défaut recommandé** : **Option B** pour le MVP — suppression physique immédiate en Storage lors du soft-delete, sauf si le document est un bail signé (`category = 'bail_signe'`) qui relève de l'obligation de conservation 5 ans (à vérifier via `legal_hold` flag ou par catégorie). La suppression immédiate est RGPD-friendly (minimisation). La corbeille (Option C) est une complexité P1.

Note : contrairement aux `receipts` (documents légaux émis), les documents uploadés n'ont pas le même statut légal immuable — un bailleur peut légitimement re-uploader une version corrigée. Le bail signé lui-même est une exception qui mérite réflexion.

### D4 — Renommage / changement de catégorie après upload : autorisé ou immuable ?

**Situation** : Le bailleur a mal catégorisé un document ("Autre" au lieu de "Bail signé").

**Options** :
- A) Immuable — aucune modification après upload (simple, sûr, mais frustrant)
- B) Catégorie éditable, nom de fichier immuable — UPDATE sur `category` uniquement, `filename` et `storage_path` sont protégés
- C) Catégorie + nom affichage éditables, `storage_path` immuable

**Défaut recommandé** : **Option B** — la catégorie est une métadonnée UI sans valeur légale, l'éditer est légitime. Le `storage_path` et le `filename` original sont immuables pour la traçabilité. Déclenche un UPDATE sur `documents.category` via RLS normale.

### D5 — Multi-upload ou un fichier à la fois ?

**Situation** : Lors d'un emménagement, le bailleur a plusieurs documents à uploader (bail, état des lieux entrant, attestation assurance).

**Options** :
- A) Un fichier à la fois — picker simple, upload séquentiel, MVP minimal
- B) Multi-upload (sélection multiple dans le picker) — batch upload, barre de progression globale
- C) Drag-and-drop multiple (Web uniquement)

**Défaut recommandé** : **Option A** pour le MVP — picker fichier unique, sans drag-and-drop. La friction est acceptable en MVP (peu de documents par bail). Le multi-upload (Option B) est P1. L'option C est P1+ (PWA, complexité Web).

---

## Scope

- Nouveau bucket Supabase Storage `documents` (privé, RLS par `landlord_id`)
- Path convention : `${env}/${landlord_id}/${lease_id}/${document_id}.{ext}` — aligné sur `Db.storagePath()`
- Nouvelle table `public.documents` + `dev.documents` (voir section Dépendances)
- Types MIME acceptés : `application/pdf`, `image/jpeg`, `image/png`, `image/webp`
- Taille max : 10 MB par fichier (cohérent avec bucket `receipts/`)
- Catégories : `bail_signe`, `etat_des_lieux`, `attestation_assurance`, `quittance_scannee`, `autre`
- UI : sous-onglet "Documents" dans `LeaseDetailPage` — liste des documents + bouton "Ajouter un document"
- Téléchargement via URL signée 5 min (ouverture dans nouvel onglet)
- Soft-delete depuis l'UI (remove de la liste) + hard-delete Storage selon D3
- Empty state : "Vos documents apparaîtront ici" (wording positif — cohérent avec PR #18)
- Upload : picker fichier unique (D5 = Option A)
- Validation MIME : client + Storage policy (D1 = Option B)

---

## Hors scope

- Page globale `/documents` (liste cross-baux) — P1
- Preview inline dans l'app (PDF renderer, image viewer) — P1, ouverture dans nouvel onglet uniquement
- Documents attachés à une propriété, un locataire ou un landlord directement (hors bail) — P1
- Multi-upload / drag-and-drop — P1
- OCR / extraction automatique de données — P2
- Partage de document avec le locataire par email — P2
- Corbeille / récupération de fichier supprimé — P1
- Versionning de document (remplacer un document existant) — P1
- Documents Office (.docx, .xlsx) — P1 (parseurs trop lourds pour le MVP)
- Numérotation ou classement automatique — P2

---

## Acceptance criteria

**AC1 — Upload happy path (PDF)**
- **Given** le bailleur est sur `LeaseDetailPage`, onglet "Documents", et le bail est actif
- **When** il clique sur "Ajouter un document", sélectionne un fichier PDF < 10 MB et choisit la catégorie "Bail signé"
- **Then** le document apparaît dans la liste avec le nom du fichier, la catégorie "Bail signé", la date d'upload (format JJ/MM/YYYY) et la taille formatée (ex : "2,4 Mo")

**AC2 — Upload happy path (image)**
- **Given** le bailleur sélectionne une image JPG, PNG ou WEBP < 10 MB avec la catégorie "État des lieux"
- **When** l'upload est validé
- **Then** le document apparaît dans la liste, accessible au téléchargement, et `documents.mime_type` est correctement renseigné

**AC3 — Affichage de la liste**
- **Given** un bail avec 3 documents uploadés (catégories différentes)
- **When** le bailleur ouvre l'onglet "Documents" de `LeaseDetailPage`
- **Then** les 3 documents sont listés avec nom, catégorie (libellé lisible en français), date d'upload et taille — triés par `uploaded_at DESC`

**AC4 — Téléchargement via URL signée**
- **Given** un document valide dans la liste
- **When** le bailleur clique sur le document (ou sur un bouton "Télécharger")
- **Then** une URL signée valable 5 min est générée, le fichier s'ouvre dans un nouvel onglet du navigateur

**AC5 — Limite taille 10 MB**
- **Given** le bailleur sélectionne un fichier > 10 MB
- **When** il tente de valider l'upload
- **Then** un message d'erreur s'affiche avant tout appel réseau : "Ce fichier dépasse la limite de 10 Mo. Sélectionnez un fichier plus petit."

**AC6 — MIME type non autorisé**
- **Given** le bailleur sélectionne un fichier avec un MIME type non supporté (ex : `.docx`, `.mp4`, `.exe`)
- **When** il tente de valider l'upload
- **Then** un message d'erreur s'affiche : "Format non supporté. Formats acceptés : PDF, JPG, PNG, WEBP."
- **And** si le fichier passe malgré tout la validation client, la Storage policy Supabase rejette l'upload avec une erreur relayée dans l'UI

**AC7 — Isolation cross-user (RLS)**
- **Given** un bailleur B authentifié tente de lire ou d'uploader un document dont `landlord_id` appartient au bailleur A
- **When** la requête Supabase est exécutée (SELECT, INSERT, ou URL signée Storage)
- **Then** zéro ligne est retournée pour le SELECT, l'INSERT est rejeté, et l'URL signée est refusée

**AC8 — Soft-delete**
- **Given** un document apparaît dans la liste
- **When** le bailleur clique sur "Supprimer" et confirme
- **Then** le document disparaît de la liste (`deleted_at` renseigné en base), et le fichier est supprimé de Supabase Storage (selon D3 = Option B)

**AC9 — Empty state**
- **Given** un bail sans aucun document uploadé
- **When** le bailleur ouvre l'onglet "Documents" de `LeaseDetailPage`
- **Then** le message "Vos documents apparaîtront ici" est affiché avec un bouton "Ajouter un document" visible

**AC10 — Édition de catégorie (selon D4)**
- **Given** un document avec la catégorie "Autre"
- **When** le bailleur modifie la catégorie en "Attestation assurance" et sauvegarde
- **Then** la liste affiche la nouvelle catégorie, `documents.category` est mis à jour en base, `filename` et `storage_path` sont inchangés

---

## Dépendances

**Tables Supabase (nouvelles)** :

Table `public.documents` + `dev.documents` :

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY DEFAULT gen_random_uuid() |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` ON DELETE RESTRICT — dénormalisé pour RLS directe |
| `lease_id` | `uuid` | NOT NULL, FK → `leases(id)` ON DELETE RESTRICT |
| `category` | `text` | NOT NULL, CHECK IN ('bail_signe', 'etat_des_lieux', 'attestation_assurance', 'quittance_scannee', 'autre') |
| `filename` | `text` | NOT NULL — nom original du fichier |
| `storage_path` | `text` | NOT NULL — chemin complet dans le bucket `documents` |
| `mime_type` | `text` | NOT NULL |
| `size_bytes` | `integer` | NOT NULL, CHECK > 0 |
| `uploaded_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `deleted_at` | `timestamptz` | NULL — soft-delete |

Index : `idx_documents_landlord_id` (RLS), `idx_documents_lease_id` (listage), `idx_documents_uploaded_at_desc` (tri).

RLS policies :
- SELECT : `landlord_id = auth.uid() AND deleted_at IS NULL`
- INSERT : WITH CHECK `landlord_id = auth.uid()`
- UPDATE : USING `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK `landlord_id = auth.uid()` — colonnes autorisées : `category` uniquement (trigger protège `storage_path`, `filename`, `deleted_at`)
- DELETE : aucune policy (soft-delete via RPC `soft_delete_document()`)

**Bucket Storage** :
- Nouveau bucket `documents` (privé, pas d'accès public)
- Policy SELECT : `auth.uid()::text = (storage.foldername(name))[2]` (aligné sur pattern `${env}/${landlord_id}/...`)
- Policy INSERT : `auth.uid()::text = (storage.foldername(name))[2]`
- Restriction MIME : `application/pdf`, `image/jpeg`, `image/png`, `image/webp`
- Taille max : 10 MB

**Tables existantes lues** :
- `leases` : lecture `landlord_id`, `tenant_id` pour validation FK
- `landlords` : via RLS auth.uid()

**Features bloquantes** :
- FEAT-005 : `LeaseDetailPage` existante (point d'entrée UI)
- FEAT-007 : pattern Storage RLS + `Db.storagePath()` établis (à réutiliser)

**Pattern Flutter à réutiliser** :
- `lib/core/db.dart` : `Db.storagePath()` pour construction du chemin
- `lib/core/utils/postgrest_error_mapper.dart` : mappage erreurs

---

## Legal / compliance notes

- **Conservation** : les documents uploadés ne sont pas des documents légaux émis (contrairement aux `receipts`). Le bailleur peut les supprimer. Exception : un bail signé peut être requis en cas de litige pendant 5 ans (prescription civile) — mais la responsabilité de conservation reste celle du bailleur. EasyRent ne garantit pas la conservation légale pour ces documents. À documenter dans `/privacy`.
- **RGPD** : la table `documents` contient des données personnelles indirectes (liées à un locataire via `lease_id`). Base légale : exécution du contrat de gestion locative (art. 6.1.b RGPD). Le droit à l'effacement s'applique pour les documents non soumis à obligation de conservation. Le soft-delete + hard-delete Storage (D3 = Option B) est conforme.
- **Accès tiers** : les URL signées expirent à 5 min. Un bailleur ne peut pas générer une URL permanente publique depuis l'UI.

---

## Risques & contraintes

| Risque | Mitigation |
|---|---|
| Fichier renommé avec extension falsifiée bypass validation client | D1 Option B : Storage policy vérifie le MIME type réel côté Supabase |
| Saturation quota Storage Supabase free tier (1 GB total) | D2 Option B : warning UI à 100 MB par landlord ; surveiller en staging |
| URL signée expirée si le bailleur tarde à ouvrir l'onglet | 5 min suffisent pour un téléchargement manuel ; régénération à chaque clic |
| `storage_path` devient orphelin si le soft-delete DB réussit mais le hard-delete Storage échoue | Logguer l'erreur Storage côté client, afficher un warning non-bloquant ; nettoyage manuel en attendant un job P1 |
| `lease_id` FK vers un bail soft-deleted | RLS filtre `leases.deleted_at IS NULL` — vérifier que le picker de bail exclut les baux archivés |

---

## Estimation

**Priorité** : P0 (MVP)

**Effort** : M (1-3 jours)

Décomposition approximative :
- Migration SQL (`documents` table + RLS + triggers + bucket policy) : 0,5 jour
- Repository + providers Flutter (upload, list, delete, signed URL) : 0,5 jour
- UI : sous-onglet `LeaseDetailPage`, liste, form upload, empty state, dialog suppression : 0,75 jour
- Tests (RLS cross-user, widget, upload/download flow) : 0,5 jour
- Intégration Storage (bucket provisioning, policy MIME) : 0,25 jour

---

## Definition of Done

- [ ] Migration `documents` appliquée (public + dev), RLS activée, trigger `prevent_protected_columns_change` posé sur `storage_path` et `filename`
- [ ] Bucket `documents` provisionné avec policy RLS SELECT/INSERT et restriction MIME
- [ ] RLS testée : bailleur B ne peut ni lire ni uploader ni télécharger des documents du bailleur A
- [ ] Upload PDF et image (JPG, PNG, WEBP) validé bout-en-bout en staging
- [ ] Erreur taille > 10 MB affichée avant upload réseau
- [ ] Erreur MIME non supporté affichée côté client et bloquée côté Storage
- [ ] Soft-delete retire le document de la liste et supprime le fichier de Storage
- [ ] URL signée 5 min fonctionne pour téléchargement dans nouvel onglet
- [ ] Empty state "Vos documents apparaîtront ici" affiché si aucun document
- [ ] Édition de catégorie (D4 Option B) fonctionnelle
- [ ] `flutter analyze` clean, `dart format` appliqué
- [ ] `code-reviewer` approuvé, `security-auditor` approuvé
- [ ] Déployé Firebase Hosting staging
