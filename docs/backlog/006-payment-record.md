# [FEAT-006] Enregistrer un paiement de loyer

## User story
En tant que **propriétaire bailleur**, je veux **enregistrer le paiement mensuel d'un loyer sur un bail actif** afin de **tracer l'historique des encaissements et débloquer la génération des quittances PDF conformes loi 6 juillet 1989**.

## Context & motivation
FEAT-005 a livré le CRUD baux — le bail est désormais l'entité pivot qui porte les montants contractuels (loyer HC + charges). FEAT-006 est le maillon suivant : sans enregistrement de paiement, impossible de générer une quittance (FEAT-007) ni de suivre les retards sur le dashboard (FEAT-009).

La distinction `rent_amount_cents` / `charges_amount_cents` dans la table `payments` est obligatoire car l'art. 21 de la loi du 6 juillet 1989 impose d'afficher ces deux montants séparément sur la quittance. Stocker un total consolidé rendrait FEAT-007 non-conforme.

## Acceptance criteria (Gherkin)

**Accès depuis la fiche bail**
- **Given** le bailleur consulte `/leases/:id` d'un bail actif
  **When** la page se charge
  **Then** une section "Paiements" liste les paiements existants (du plus récent au plus ancien), et un bouton "Ajouter un paiement" est visible.

- **Given** le bail a le statut `terminated` ou `archived`
  **When** le bailleur tente d'ouvrir le formulaire d'ajout
  **Then** le bouton est désactivé avec le message "Ce bail est clôturé."

**Formulaire d'ajout de paiement**
- **Given** le bailleur clique sur "Ajouter un paiement"
  **When** le formulaire s'ouvre
  **Then** les champs suivants sont présents :
  - Période de début (date picker, obligatoire, pré-rempli au 1er du mois courant)
  - Période de fin (date picker, obligatoire, pré-rempli au dernier jour du mois courant)
  - Date de paiement effective (date picker, obligatoire, pré-rempli à aujourd'hui)
  - Loyer hors charges en euros (obligatoire, numérique positif, pré-rempli depuis `lease.rent_amount_cents`, format `1 234,56 €`)
  - Charges en euros (obligatoire, 0 accepté, pré-rempli depuis `lease.charges_amount_cents`)
  - Mode de paiement (dropdown obligatoire : virement, chèque, espèces, prélèvement, autre)
  - Notes (texte libre, optionnel, max 500 caractères)
  - Total calculé affiché en lecture seule : loyer HC + charges

- **Given** le bailleur soumet un formulaire valide
  **When** l'insertion Supabase réussit
  **Then** le paiement apparaît en tête de liste sur la fiche bail, un toast "Paiement enregistré" s'affiche, et les montants sont affichés au format `1 234,56 €` (locale fr_FR).

- **Given** le total saisi (loyer + charges) est strictement inférieur au montant du bail
  **When** le formulaire est rempli
  **Then** un message d'avertissement non bloquant s'affiche : "Montant inférieur au bail — un reçu sera émis (pas une quittance libératoire)." L'utilisateur peut soumettre malgré tout.

- **Given** le total saisi est strictement supérieur au montant du bail
  **When** le formulaire est rempli
  **Then** un message informatif non bloquant s'affiche : "Montant supérieur au bail — vérifiez s'il s'agit d'une régularisation."

- **Given** la période de fin est antérieure à la période de début
  **When** la validation côté client s'exécute
  **Then** un message d'erreur "La fin de période doit être postérieure au début" s'affiche et aucun appel Supabase n'est effectué.

- **Given** le loyer saisi est négatif ou non-numérique
  **When** la validation côté client s'exécute
  **Then** un message d'erreur inline s'affiche sur le champ concerné.

**Modification d'un paiement**
- **Given** le bailleur clique sur un paiement existant dans la liste
  **When** le formulaire d'édition s'ouvre
  **Then** tous les champs sont modifiables (sauf `lease_id` qui est fixe).

- **Given** le bailleur soumet des modifications valides
  **When** l'UPDATE Supabase réussit
  **Then** la liste affiche les nouvelles valeurs, `updated_at` est mis à jour, un toast "Paiement mis à jour" s'affiche.

**Suppression (soft-delete)**
- **Given** le bailleur clique sur "Supprimer" sur un paiement
  **When** une dialog de confirmation "Supprimer ce paiement ?" s'affiche et est confirmée
  **Then** `deleted_at = now()` est positionné via RPC, le paiement disparaît de la liste, un toast "Paiement supprimé" s'affiche.

- **Given** un paiement est soft-deleted
  **When** une quittance pour la même période est demandée (FEAT-007)
  **Then** ce paiement n'est pas inclus.

**Isolation RLS**
- **Given** un propriétaire B tente d'accéder aux paiements d'un bail appartenant au propriétaire A
  **When** la requête Supabase est exécutée
  **Then** zéro ligne est retournée (RLS via jointure `payments → leases → landlord_id = auth.uid()`).

**Vue liste paiements (page dédiée optionnelle)**
- **Given** le bailleur navigue vers `/payments` (ou filtre sur `/leases/:id`)
  **When** des filtres sont appliqués (bail, mois, statut)
  **Then** seuls les paiements correspondant aux critères sont affichés.

## Modèle de données

### Table `payments` (public + dev)

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PRIMARY KEY, DEFAULT gen_random_uuid() |
| `lease_id` | `uuid` | NOT NULL, FK → `leases(id)` ON DELETE RESTRICT |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` ON DELETE RESTRICT — dénormalisé pour RLS directe sans jointure |
| `period_start` | `date` | NOT NULL — 1er jour de la période couverte |
| `period_end` | `date` | NOT NULL — dernier jour de la période couverte, CHECK period_end > period_start |
| `paid_at` | `date` | NOT NULL — date de réception effective du paiement |
| `rent_amount_cents` | `integer` | NOT NULL, CHECK > 0 — loyer HC en centimes |
| `charges_amount_cents` | `integer` | NOT NULL DEFAULT 0, CHECK >= 0 — charges en centimes |
| `payment_method` | `text` | NOT NULL, CHECK IN ('virement', 'cheque', 'especes', 'prelevement', 'autre') |
| `notes` | `text` | NULL, CHECK length <= 500 |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `deleted_at` | `timestamptz` | NULL — soft-delete, modifiable uniquement via RPC `soft_delete_payment()` |

**Index suggérés** : `idx_payments_lease_id`, `idx_payments_landlord_id`, `idx_payments_period_start` (tri chronologique), index partiel `WHERE deleted_at IS NULL`.

**Distinction loyer / charges — obligation légale** : La loi du 6 juillet 1989 (art. 21) impose d'afficher le loyer HC et les charges séparément sur la quittance. FEAT-007 lira directement `rent_amount_cents` et `charges_amount_cents`. Stocker un montant total unique rendrait la quittance non-conforme.

### RLS

Policy unique suffisante (via `landlord_id` dénormalisé) :

| Policy | Opération | Condition |
|---|---|---|
| `payments_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` |
| `payments_insert_own` | INSERT | WITH CHECK: `landlord_id = auth.uid()` |
| `payments_update_own` | UPDATE | USING: `landlord_id = auth.uid() AND deleted_at IS NULL` / WITH CHECK: `landlord_id = auth.uid()` |

Pas de policy DELETE (soft-delete via RPC `soft_delete_payment(p_id uuid)` suivant le pattern FEAT-002).

Un trigger `assert_payment_lease_ownership()` SECURITY DEFINER devra valider que `lease.landlord_id = NEW.landlord_id` à l'INSERT et UPDATE (cohérence cross-FK, même pattern que `assert_lease_ownership_consistency`).

### Migration

Nouvelle migration `20260601XXXXXX_feat006_payments.sql` (à dater à la création) — appliquée aux schémas `public` ET `dev` conformément à la règle multi-env (`docs/ENVIRONMENTS.md`).

## UI/UX

- **Point d'entrée principal** : section "Paiements" sur `/leases/:id` (référencée depuis FEAT-005, actuellement vide).
- **Liste des paiements** : colonnes — période, date paiement, loyer HC, charges, total, mode, actions (éditer / supprimer). Tri : `period_start DESC`.
- **Formulaire** : modal ou page dédiée `/leases/:id/payments/new` et `/leases/:id/payments/:pid/edit` — à trancher par l'architect selon les conventions de navigation existantes.
- **Pré-remplissage** : les montants sont pré-remplis depuis le bail (`lease.rent_amount_cents`, `lease.charges_amount_cents`) pour réduire les saisies répétitives — le bailleur peut les ajuster pour un mois donné (ex. régularisation ponctuelle).
- **Affichage montants** : format `1 234,56 €` (espace insécable, virgule décimale, € à droite, locale fr_FR) — même helper que FEAT-005.

## Out of scope
- Génération du PDF quittance (FEAT-007 — dépend de FEAT-006)
- Envoi par email (FEAT-008)
- Rappels automatiques de loyer impayé (P2)
- Gestion des trop-perçus / remboursements
- Rapprochement bancaire automatique
- Hard-delete (jamais)

## Dependencies
- Tables Supabase : `payments` (nouvelle), `leases`, `landlords` (FEAT-002)
- Features bloquantes : FEAT-001 (auth), FEAT-002 (schéma + RLS pattern), FEAT-005 (bail doit exister et être actif)
- Feature débloquée : FEAT-007 (quittance PDF) — lit directement `payments` pour générer la quittance conforme

## Legal / compliance notes
- **Loi du 6 juillet 1989, art. 21** : `rent_amount_cents` et `charges_amount_cents` doivent être stockés séparément — FEAT-007 les affichera distincts sur la quittance. Un paiement partiel ne peut pas générer une quittance (seulement un reçu avec mention "ne libère pas le locataire du solde").
- **Conservation 5 ans** : les paiements ont une valeur légale et fiscale. Soft-delete uniquement, jamais de hard-delete. La migration doit inclure le trigger `prevent_protected_columns_change` sur `deleted_at` et `created_at` (pattern FEAT-002).
- **RGPD** : les paiements contiennent des données personnelles (liées au locataire via `lease_id`). Export des données (`GET /export`, P1) devra inclure les paiements. Soft-delete au lieu d'effacement lors du droit à l'oubli.
- **Format montants** : centimes (integer) — pas de float pour éviter les erreurs d'arrondi sur les montants légaux. Conversion euros ↔ centimes côté client, jamais côté base.

## Décisions produit (tranchées 2026-05-31)

1. **Paiements partiels — libre + warning UI** : le bailleur peut saisir n'importe quel montant. Si `rent_amount_cents + charges_amount_cents < lease.rent_amount_cents + lease.charges_amount_cents`, l'UI affiche un warning non bloquant (« Montant inférieur au bail — un reçu sera émis à la place d'une quittance »). FEAT-007 devra distinguer quittance (= libératoire, montant complet) vs reçu (partiel) selon la loi 1989.

2. **Doublons de période autorisés** : pas de contrainte unique sur `(lease_id, period_start, period_end)`. Plusieurs paiements peuvent couvrir la même période (paiement fractionné, complément, etc.). FEAT-007 sommera les paiements d'une période avant émission de la quittance/reçu.

## Risques et questions encore ouvertes

1. **Trop-perçus** : un paiement supérieur aux montants du bail est autorisé (cas régularisation de charges). UI affichera un warning informatif similaire au paiement partiel mais sans blocage.

2. **Date de période vs date de paiement** : la `period_start` / `period_end` couvre la période locative (ex. 01/06 → 30/06) tandis que `paid_at` est la date d'encaissement réelle. Ces deux concepts sont distincts et doivent coexister — confirmé par le modèle ci-dessus, mais à valider avec un cas réel (loyer du mois M payé le 30/M-1 ou le 05/M+1).

## Priority
P0 (MVP)

## Estimated effort
M (1-3 jours)

## Definition of Done
- [ ] Code formaté, `flutter analyze` clean
- [ ] Migration `payments` appliquée (public + dev), RLS activée, trigger `prevent_protected_columns_change` posé
- [ ] RLS testée : un propriétaire B ne peut ni lire ni modifier les paiements du propriétaire A
- [ ] Trigger `assert_payment_lease_ownership` validé : impossible d'insérer un paiement sur un bail appartenant à un autre landlord
- [ ] Tests widget : formulaire création (validation montants, dates, mode), formulaire édition, soft-delete
- [ ] Conversion centimes ↔ euros testée (arrondi, cas limites)
- [ ] Pré-remplissage depuis `lease.rent_amount_cents` / `lease.charges_amount_cents` testé
- [ ] Bail clôturé → bouton "Ajouter un paiement" désactivé testé
- [ ] `code-reviewer` approuvé, `security-auditor` approuvé
- [ ] Déployé sur Firebase Hosting (env dev)
