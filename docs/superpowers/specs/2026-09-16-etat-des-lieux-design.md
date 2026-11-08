# FEAT-037 — État des lieux digital (V1) — Design

> **Statut** : Design validé (brainstorm 2026-09-16). Prêt pour `writing-plans` après revue utilisateur.
> **Domaine** : leases (fiche bail) + nouvelle collection `etat_des_lieux`.
> **Dépend de** : FEAT-005 (baux) ✅, FEAT-007 (renderer PDF `pdf`) ✅, patron `charge_statements` (FEAT-033) ✅.

## Problème

Aujourd'hui un état des lieux (EDL) n'existe dans l'app que comme **catégorie de document** (`etat_des_lieux`) : le bailleur uploade un PDF rédigé ailleurs (papier, Word). Aucun flux de **rédaction in-app**. L'EDL est pourtant un document légal obligatoire (loi du 6 juillet 1989 art. 3-2 ; contenu fixé par le **décret n°2016-382**), à valeur probante en cas de litige sur le dépôt de garantie.

FEAT-037 V1 permet de **rédiger** un EDL conforme dans l'app et d'en produire un **PDF** rattaché au bail.

## Décision d'architecture (transparence de cadrage)

Le brainstorm avait évoqué « sans backend lourd ». Après vérification, l'EDL est un **document légal à valeur probante**, de même nature que les quittances (`receipts`) et les régularisations figées (`charge_statements`) — tous deux stockés en **collection immuable CF-exclusive**. V1 suit cette convention plutôt que de stocker un PDF plat :

- **Nouvelle collection `etat_des_lieux/{id}`**, immuable, CF-exclusive (patron `charge_statements` / FEAT-033).
- **Callable `createEtatDesLieux`** (valide l'ownership du bail, fige un snapshot des parties/adresse — loi 6/7/1989 — puis écrit).
- **PDF généré côté client à la demande** depuis le snapshot (patron `receipt_pdf_renderer.dart` — `pdfPath` jamais persisté), pas de Storage serveur.

**Conséquence sous le gel GitHub Actions (Plan A)** : le déploiement des **functions** (manuel) et des **rules + index** (normalement CI) est **reporté au reset du quota**. Le code est mergé sur `develop` (vert en local), déployé plus tard. Rien ne casse en attendant (la feature n'est simplement pas active en staging tant que la callable n'est pas déployée).

Bénéfice : données structurées **persistées et ré-ouvrables**, base saine pour la comparaison entrée↔sortie de V2.

## Périmètre

### Inclus (V1) — le noyau obligatoire du décret 2016-382
- **Type** : entrée **ou** sortie (champ `type`), **date**, **adresse** du logement (snapshot bail), **parties** (bailleur + locataire, snapshot bail).
- **Pièces + éléments** : liste de pièces, chacune avec des éléments (murs, sol, plafond, équipements…) portant un **état** (`neuf` / `bon` / `moyen` / `mauvais`) + commentaire libre optionnel.
- **Relevés compteurs** : eau / électricité / gaz — valeur d'index (chacun optionnel : tous les logements n'ont pas les 3).
- **Nombre de clés** remises.
- **Commentaire général** optionnel.
- **PDF conforme** (blocs de signature manuscrite imprimables) rattaché au bail ; **liste des EDL** du bail + consultation/(re)génération PDF (patron `LeaseReceiptsPage`).
- **Template par défaut** de pièces/éléments à la création (Séjour, Chambre, Cuisine, Salle de bain, WC × murs/sol/plafond/équipements) — éditable/supprimable — pour éviter la page blanche.
- i18n FR/EN.

### Exclus (V2 — cuts validés 2026-09-16)
- **Photos** par pièce/élément (Storage + quota + UX upload) — *non obligatoires au décret*.
- **Signature électronique** à l'écran (V1 : le PDF porte des blocs de signature, signés sur papier après impression ; aucun package signature dans le repo).
- **Comparaison entrée↔sortie** automatique + retenues sur dépôt de garantie.
- Édition/annulation d'un EDL après création (immuable ; une erreur = nouvel EDL). Un `void`/archivage éventuel = V2.

## Composants

### 1. Modèles (freezed) — `lib/features/etat_des_lieux/domain/`
- `EtatDesLieux` : `id`, `landlordId`, `leaseId`, `type` (`EtatDesLieuxType.entree|sortie`), `date`, `propertyAddress`, `landlordFullName`, `tenantFullName` (snapshots), `rooms: List<EdlRoom>`, `meterReadings: EdlMeterReadings`, `keysCount: int`, `generalComment: String?`, `createdAt`.
- `EdlRoom` : `name`, `elements: List<EdlElement>`.
- `EdlElement` : `name`, `condition` (`EdlCondition.neuf|bon|moyen|mauvais`), `comment: String?`.
- `EdlMeterReadings` : `waterIndex: String?`, `electricityIndex: String?`, `gasIndex: String?` (chaînes libres : relevés parfois non purement numériques).
- `EtatDesLieuxType` (enum + `sqlValue` snake_case, patron `DocumentCategory`), `EdlCondition` (enum + label i18n).

### 2. Callable — `functions/src/callable/etat_des_lieux.ts`
- `createEtatDesLieux(request)` : `requireAuthUid` ; valide `leaseId` possédé par `uid` + non supprimé (patron `createDocument`/`charge_statements`) ; **fige** `propertyAddress` + noms des parties depuis le bail (immutabilité loi) ; valide `type ∈ {entree,sortie}`, `condition` de chaque élément ∈ enum, `keysCount >= 0` ; écrit `etat_des_lieux/{autoId}` (immuable). **Retour** `{etatDesLieuxId}`. `dbForRequest(request)` (ADR 0003).
- Export dans `index.ts`, region `europe-west1`.

### 3. Rules + index
- `firestore.rules` : `match /etat_des_lieux/{id}` — `get,list: if isOwner(resource.data.landlordId)` ; `create,update,delete: if false` (CF-exclusive, patron `charge_statements`).
- `firestore.indexes.json` : index composite `(landlordId, leaseId, createdAt desc)` pour la liste par bail.

### 4. PDF — `lib/features/etat_des_lieux/data/etat_des_lieux_pdf_renderer.dart`
- Génère le PDF conforme décret 2016-382 depuis un `EtatDesLieux` (patron `receipt_pdf_renderer.dart`, polices `pdf_brand_fonts.dart`). Sections : en-tête (type, date, adresse, parties), tableau pièces/éléments/états/commentaires, relevés compteurs, nombre de clés, commentaire général, **blocs de signature** (bailleur + locataire, date/lieu) imprimables.

### 5. Repository — `lib/features/etat_des_lieux/data/etat_des_lieux_repository.dart`
- `create(...)` → appelle la callable, relit le doc créé.
- `listForLease(leaseId)` → requête owner-scopée triée `createdAt desc`.
- `getById(id)`. Accès via `firestoreProvider` (jamais `.instance`).

### 6. UI — `lib/features/etat_des_lieux/presentation/`
- **`EtatDesLieuxListPage`** (`/leases/:id/etat-des-lieux`) : liste des EDL du bail (type + date + bouton PDF), CTA « Nouvel état des lieux ». Patron `LeaseReceiptsPage`.
- **`EtatDesLieuxFormPage`** (`/leases/:id/etat-des-lieux/new`) : formulaire multi-sections — type (entrée/sortie) + date ; pièces (ajouter/supprimer, éléments avec `DropdownButton` état + commentaire), pré-rempli par le template par défaut ; compteurs (3 champs optionnels) ; clés ; commentaire général. Bouton « Générer » → `create` → ouvre le PDF.
- Contrôleur `application/etat_des_lieux_form_controller.dart` (état sealed submitting/success/error, patron des autres flux d'écriture).
- Entrée depuis `lease_detail_page.dart` : une tuile/section « États des lieux » (accès à la liste).

## Données disponibles (vérifié)
- Bail : `landlordId`, `propertyAddress` (composé, immuable), `tenantFirstName`/`tenantLastName`, `landlordFullName` (profil) — snapshots pour l'immutabilité.
- Renderer PDF : `pdf: ^3.11.0`, patrons `receipt_pdf_renderer.dart` / `charge_regularization_pdf_renderer.dart`, polices `pdf_brand_fonts.dart`.
- Patron collection immuable : `charge_statements` (rules `firestore.rules:346`, callable `charge_statements.ts`).

## Gestion d'erreur
- Callable refuse : bail non possédé / supprimé (`permission-denied` / `failed-precondition`), `type`/`condition` invalide (`invalid-argument`). Le client mappe vers un message i18n (patron `UpdateCategoryErrorReason`).
- `launchUrl`/ouverture PDF échoue → SnackBar (patron quittances).
- EDL sans aucune pièce : autorisé mais alerte douce (un EDL vide a peu de valeur) — non bloquant.

## i18n
Clés FR/EN (`@description` template EN, parité `arb_parity_test`) : titres pages, type entrée/sortie, labels états (neuf/bon/moyen/mauvais), sections (pièces, compteurs eau/élec/gaz, clés, commentaire), template pièces/éléments par défaut, libellés PDF (peuvent rester dans le renderer), erreurs. `flutter gen-l10n`.

## Tests
- **Unit (pur)** : modèles + enums (`sqlValue`, labels) ; template par défaut ; validation (keysCount, condition).
- **Functions (vitest + FakeFirestore)** : `createEtatDesLieux` — happy path (snapshot parties/adresse figés), refus bail non possédé / supprimé, `type`/`condition` invalide, immutabilité (rules).
- **Rules** : `etat_des_lieux` get/list owner-scoped, create/update/delete refusés client (cross-user).
- **Repository** (`fake_cloud_firestore`) : `listForLease` tri + owner-scope ; `create` appelle la callable.
- **Widget** : form rend le template ; ajout/suppression pièce/élément ; changement d'état ; génération appelle le contrôleur ; liste affiche les EDL.
- **PDF** : test de fumée du renderer (génère des bytes non vides pour un EDL complet) — patron test renderer quittance s'il existe.
- **i18n** : `arb_parity_test` vert.

## Definition of Done (docs d'état)
`state-keeper` : `docs/state/schema/leases.md` (ou nouveau shard) — collection `etat_des_lieux` ; `docs/state/functions/leases.md` — callable `createEtatDesLieux` ; `docs/state/routes/leases.md` — routes EDL ; `FEATURES.md` (FEAT-037 → ✅ done) ; `CHANGELOG.md` ; `INDEX.md` (décompte collections 11→12, callables +1, index +1).

**Déploiement (Plan A, gel Actions)** : functions (manuel `firebase deploy --only functions`) + rules/index (manuel ou CI au reset quota) **reportés**. À lister dans le récap post-merge.

## Légal / conformité
- **Décret n°2016-382** : contenu minimal de l'EDL couvert par V1 (type, date, localisation, parties, relevés compteurs, description contradictoire pièce par pièce, clés, blocs signature). Les photos ne sont pas obligatoires.
- **Immutabilité** (loi 6/7/1989) : snapshot des parties/adresse figé à la création, collection non modifiable client — même garantie que quittances/régul.
- **RGPD** : données déjà détenues (bail, locataire) ; aucune nouvelle base légale ; rien ne quitte l'appareil hormis l'écriture Firestore du bailleur.

## Hors scope (V2)
Photos, signature électronique à l'écran, comparaison entrée↔sortie + retenues dépôt de garantie, édition/void d'un EDL, envoi de l'EDL au locataire (réutilisera le patron relance/partage FEAT-031/quittances).
