# [FEAT-007] Générer une quittance PDF de loyer

## User story
En tant que **propriétaire bailleur**, je veux **générer un document PDF (quittance ou reçu) pour une période de location** afin de **satisfaire mon obligation légale (loi du 6 juillet 1989, art. 21) et fournir au locataire une preuve de paiement conforme**.

## Context & motivation
FEAT-006 a livré l'enregistrement des paiements avec la séparation obligatoire `rent_amount_cents` / `charges_amount_cents`. FEAT-007 est la finalité immédiate : transformer ces données en un document PDF légalement conforme.

Deux types de documents sont requis par la loi :
- **Quittance** (libératoire) : émise uniquement si le total encaissé sur la période est **égal ou supérieur** au loyer + charges contractuels. Elle libère le locataire de sa dette pour cette période.
- **Reçu** (non libératoire) : émis si le total encaissé est **inférieur** au loyer + charges contractuels. La mention "ne libère pas le locataire du solde dû" est obligatoire.

Plusieurs paiements peuvent couvrir une même période (FEAT-006 autorise les doublons). Avant émission, FEAT-007 somme tous les paiements actifs (`deleted_at IS NULL`) de la période, puis applique la règle quittance vs reçu.

FEAT-008 (envoi email) lira directement les enregistrements générés par FEAT-007 (table `receipts`, colonne `pdf_url`). L'architecture doit rendre `pdf_url` accessible depuis FEAT-008 sans re-génération.

## Acceptance criteria (Gherkin)

**Déclenchement depuis la fiche paiement**
- **Given** le bailleur consulte un paiement actif sur `/leases/:id`
  **When** il clique sur "Générer quittance"
  **Then** le système calcule la somme des paiements actifs de la même période (`period_start` / `period_end`), détermine le type de document (quittance ou reçu), génère le PDF et l'affiche ou le propose au téléchargement.

**Déclenchement depuis la période**
- **Given** le bailleur ouvre `/leases/:id/receipts` et sélectionne une période (ex. "mai 2026")
  **When** il clique sur "Générer quittance pour cette période"
  **Then** le système additionne tous les paiements actifs de la période, détermine quittance vs reçu et génère le PDF.

**Choix automatique quittance vs reçu**
- **Given** la somme des paiements actifs pour la période est >= `lease.rent_amount_cents + lease.charges_amount_cents`
  **When** le document est généré
  **Then** le document est typé `quittance`, porte le titre "Quittance de loyer" et ne contient aucune mention de solde résiduel.

- **Given** la somme des paiements actifs pour la période est < `lease.rent_amount_cents + lease.charges_amount_cents`
  **When** le document est généré
  **Then** le document est typé `recu`, porte le titre "Reçu de paiement" et contient la mention obligatoire : "Ce reçu ne libère pas le locataire du solde dû pour la période concernée."

**Conformité PDF (mentions obligatoires art. 21 loi 1989)**
- **Given** un document PDF est généré (quittance ou reçu)
  **When** son contenu est vérifié
  **Then** il contient obligatoirement :
  1. Titre clair : "Quittance de loyer" ou "Reçu de paiement"
  2. Nom et adresse du bailleur (`landlords.full_name`, `landlords.address`)
  3. Nom du locataire (`tenants.first_name + last_name`)
  4. Adresse du logement (`properties.address`)
  5. Période couverte (`period_start` → `period_end` au format DD/MM/YYYY)
  6. Montant du loyer hors charges (format `1 234,56 €`)
  7. Montant des charges (format `1 234,56 €`)
  8. Montant total reçu (format `1 234,56 €`)
  9. Date d'établissement du document (format DD/MM/YYYY)
  10. Mention "ne libère pas le locataire du solde dû" si `recu`

**Idempotence et traçabilité**
- **Given** un document a déjà été généré pour une période donnée d'un bail
  **When** le bailleur demande une nouvelle génération pour la même période
  **Then** le système propose soit de télécharger le document existant, soit d'en générer un nouveau (le précédent est conservé, non écrasé).

- **Given** un document PDF est généré avec succès
  **When** la génération est terminée
  **Then** un enregistrement est créé dans la table `receipts` (voir section "Modèle de données") et le bailleur peut accéder à la liste des documents depuis `/leases/:id/receipts`.

**Cas d'erreur**
- **Given** le bail référencé n'existe pas ou est soft-deleted
  **When** la génération est demandée
  **Then** un message d'erreur "Bail introuvable" s'affiche, aucun PDF n'est généré.

- **Given** le bailleur n'a aucun paiement actif pour la période sélectionnée
  **When** la génération est demandée
  **Then** un message "Aucun paiement enregistré pour cette période" s'affiche.

- **Given** `landlords.full_name` ou `landlords.address` est NULL
  **When** la génération est demandée
  **Then** un message d'avertissement indique "Complétez votre profil (nom + adresse) avant de générer une quittance" et bloque la génération.

**Invalidation**
- **Given** un paiement inclus dans un document généré est ensuite soft-deleted
  **When** le bailleur consulte le document dans `/leases/:id/receipts`
  **Then** le document porte la mention visuelle "Données modifiées — un ou plusieurs paiements ont été supprimés après l'émission" (colonne `is_stale` = true sur `receipts`). Le PDF existant n'est pas supprimé (rétention légale 5 ans).

**Isolation RLS**
- **Given** un propriétaire B tente d'accéder à un reçu appartenant au propriétaire A
  **When** la requête Supabase est exécutée
  **Then** zéro ligne est retournée (`receipts.landlord_id = auth.uid()`).

## Mentions obligatoires PDF (art. 21 loi du 6 juillet 1989)

Liste exhaustive à vérifier dans les tests d'acceptance :

| Champ | Source | Format |
|---|---|---|
| Titre du document | Calculé (quittance vs recu) | "Quittance de loyer" / "Reçu de paiement" |
| Nom du bailleur | `landlords.full_name` | Texte |
| Adresse du bailleur | `landlords.address` | Texte |
| Nom du locataire | `tenants.first_name + last_name` | Texte |
| Adresse du logement | `properties.address` | Texte |
| Période couverte | `period_start → period_end` | DD/MM/YYYY → DD/MM/YYYY |
| Loyer hors charges | `receipts.rent_cents` | `1 234,56 €` |
| Charges | `receipts.charges_cents` | `1 234,56 €` |
| Total reçu | `receipts.total_cents` | `1 234,56 €` |
| Date d'établissement | `receipts.generated_at` | DD/MM/YYYY |
| Mention solde (si reçu) | `receipts.document_type = 'recu'` | Texte fixe obligatoire |

## Modèle de données

### Table `receipts` (public + dev)

Recommandation : créer cette table pour la traçabilité, l'idempotence et le lien depuis FEAT-008.

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `lease_id` | `uuid` | NOT NULL, FK → `leases(id)` ON DELETE RESTRICT |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` ON DELETE RESTRICT — dénormalisé pour RLS directe |
| `payment_ids` | `uuid[]` | NOT NULL — liste des `payments.id` inclus dans ce document |
| `period_start` | `date` | NOT NULL |
| `period_end` | `date` | NOT NULL, CHECK > period_start |
| `rent_cents` | `integer` | NOT NULL, CHECK > 0 — somme `rent_amount_cents` des paiements inclus |
| `charges_cents` | `integer` | NOT NULL DEFAULT 0, CHECK >= 0 — somme `charges_amount_cents` |
| `total_cents` | `integer` | NOT NULL, CHECK > 0 — rent_cents + charges_cents |
| `document_type` | `text` | NOT NULL, CHECK IN ('quittance', 'recu') |
| `generated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `generated_by` | `uuid` | NOT NULL, FK → `auth.users(id)` — auditabilité |
| `pdf_url` | `text` | NULL — URL Supabase Storage après upload ; NULL si stockage désactivé |
| `is_voided` | `boolean` | NOT NULL DEFAULT false — annulation manuelle (ne supprime pas le PDF) |
| `is_stale` | `boolean` | NOT NULL DEFAULT false — true si un payment_id inclus a été soft-deleted après l'émission |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |

**Index** : `idx_receipts_landlord_id`, `idx_receipts_lease_id`, `idx_receipts_period_start_desc`.

**RLS** :

| Policy | Opération | Condition |
|---|---|---|
| `receipts_select_own` | SELECT | `landlord_id = auth.uid()` |
| `receipts_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |

Pas de policy UPDATE ni DELETE (les reçus sont immutables une fois générés — `is_voided` et `is_stale` sont mis à jour via RPC uniquement).

**Conservation** : jamais de hard-delete (`receipts` ont une valeur légale — 5 ans minimum, RGPD art. 17 §3).

### Impact sur les tables existantes

Aucune modification de `payments` ou `leases` requise. Les montants sont lus directement depuis `payments.rent_amount_cents` / `payments.charges_amount_cents`.

## Architecture — question ouverte pour l'architecte

Deux options pour la génération PDF :

**Option A — Côté client Flutter Web** (`pdf` + `printing` packages)
- Avantages : pas de backend, pas de latence réseau, implémentation immédiate.
- Inconvénients : le PDF n'est pas signé ni traçable côté serveur ; le stockage dans Supabase Storage nécessite un upload supplémentaire depuis le client ; la logique de génération ne bénéficie pas du moteur Supabase côté serveur.

**Option B — Edge Function Supabase (Deno + `pdfme` ou `pdfkit`)**
- Avantages : génération traçable et idempotente côté serveur ; `pdf_url` renvoyée directement ; partage naturel avec FEAT-008 (la même Edge Function peut déclencher l'envoi via Resend sans re-génération côté client).
- Inconvénients : première Edge Function du projet (complexité d'amorçage) ; FEAT-008 dépend alors d'un service Deno opérationnel.

**Recommandation produit** : laisser l'architecte trancher. Cependant, étant donné que FEAT-008 (envoi email) nécessitera une Edge Function Resend de toute façon, l'Option B mutualise l'infrastructure. Si FEAT-007 est en Option A, FEAT-008 devra tout de même créer une Edge Function qui appellera `pdf_url` stockée dans `receipts` — ce qui suppose que le PDF soit stocké dans Supabase Storage. L'architecte doit donc trancher conjointement Option A+Storage ou Option B.

## Stockage PDF

- **Avec stockage** : bucket Supabase Storage `receipts/` (chemin `{landlord_id}/{lease_id}/{receipt_id}.pdf`), RLS en lecture restreinte au `landlord_id`. `pdf_url` est une URL signée (expiration paramétrable) ou URL publique selon la politique de confidentialité choisie. FEAT-008 passe `pdf_url` à Resend directement.
- **Sans stockage** : le PDF est généré à la demande et téléchargé directement (pas de `pdf_url`). FEAT-008 devra re-générer à chaque envoi ou recevoir le PDF en base64. Moins robuste pour la traçabilité et la rétention légale.
- **Recommandation** : stockage dans Supabase Storage (bucket `receipts/`) — obligatoire pour la rétention légale 5 ans et pour que FEAT-008 passe l'URL à Resend sans re-génération.

## UI/UX

- **Point d'entrée 1** : bouton "Générer quittance" sur chaque ligne de `PaymentListSection` (déjà présent dans `LeaseDetailPage` FEAT-005/006).
- **Point d'entrée 2** : page `/leases/:id/receipts` — liste des documents émis pour ce bail (date, période, type, montant, actions : télécharger, envoyer par email via FEAT-008).
- **Prévisualisation** : modal ou page dédiée avant téléchargement final — à trancher par l'architecte selon les conventions de navigation existantes.
- **Nommage suggéré** : `quittance_{year}_{month}_{lease_id_short}.pdf` ou séquentiel annuel (voir questions ouvertes).

## Out of scope
- Envoi par email (FEAT-008 — lit `receipts.pdf_url`)
- Tampon, signature électronique qualifiée (eIDAS)
- Multi-langue (FR uniquement)
- Archivage légal certifié (tiers-archivage)
- Régularisation annuelle de charges (P2)
- Numérotation séquentielle annuelle officielle (P1 — UUID suffit pour le MVP)

## Dependencies
- Tables Supabase : `receipts` (nouvelle), `payments`, `leases`, `tenants`, `properties`, `landlords`
- Features bloquantes : FEAT-006 (paiements doivent exister)
- Feature débloquée : FEAT-008 (envoi email lit `receipts.pdf_url`)
- Bucket Storage : `receipts/` à provisionner (noté dans la dette technique BACKLOG.md)

## Legal / compliance notes
- **Loi du 6 juillet 1989, art. 21** : toutes les mentions listées dans la section "Mentions obligatoires" sont requises. L'omission d'une mention rend le document non conforme.
- **Distinction quittance / reçu** : ne jamais émettre une quittance sur un paiement partiel. La règle de calcul (somme des paiements actifs vs loyer+charges contractuels) doit être testée exhaustivement.
- **Conservation 5 ans** : `receipts` ne doivent jamais être hard-deleted. Soft-delete interdit aussi (document légal). Seul `is_voided` peut être positionné à true.
- **RGPD** : les `receipts` contiennent des données personnelles (locataire, bailleur, montants). Exception au droit à l'effacement (art. 17 §3 RGPD) : obligation légale de conservation 5 ans. À documenter dans `/privacy`.
- **Formats** : dates en DD/MM/YYYY, montants en `1 234,56 €` (locale fr_FR), mois en français ("Loyer de mai 2026").

## Risques et questions ouvertes

1. **Option A vs Option B (génération PDF)** — bloquant pour l'architecte. À trancher avant démarrage.
2. **Bail terminé/archivé** : une quittance rétroactive doit-elle être possible ? Décision produit requise. Hypothèse MVP : oui, autorisée (régularisations fréquentes en fin de bail).
3. **Paiement soft-deleted après émission** : le document reste valide mais `is_stale` est positionné à true. Un trigger ou un job de maintenance devra détecter ce cas. À trancher : trigger Postgres sur `payments.deleted_at` ou job Flutter au chargement ?
4. **Numérotation des quittances** : UUID suffit pour le MVP ; une numérotation séquentielle annuelle (ex. "2026-001") est une bonne pratique mais complexifie le schéma (séquence par landlord × année). À différer en P1.
5. **`landlords.full_name` et `landlords.address` peuvent être NULL** (colonnes optionnelles FEAT-002) : la génération doit les exiger non-null. Décision : bloquer la génération avec message d'avertissement (voir AC ci-dessus) ou forcer la saisie lors du premier accès à FEAT-007 ?

## Priority
P0 (MVP)

## Estimated effort
M (1-3 jours)

## Definition of Done
- [ ] Code formaté, `flutter analyze` clean
- [ ] Migration `receipts` appliquée (public + dev), RLS activée, trigger `prevent_protected_columns_change` posé
- [ ] RLS testée : un propriétaire B ne peut ni lire ni créer des reçus appartenant au propriétaire A
- [ ] Logique quittance vs reçu testée (cas : paiement exact, partiel, somme multi-paiements)
- [ ] PDF contient toutes les mentions obligatoires art. 21 (testé unitairement sur le contenu du PDF ou via snapshot)
- [ ] `is_stale` positionné correctement si paiement inclus est soft-deleted après émission
- [ ] Bucket `receipts/` provisionné avec RLS Storage (lecture restreinte au landlord_id)
- [ ] `code-reviewer` approuvé, `security-auditor` approuvé
- [ ] Déployé sur Firebase Hosting (env dev)
