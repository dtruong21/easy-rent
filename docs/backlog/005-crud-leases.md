# [FEAT-005] CRUD baux

## User story
En tant que **propriétaire bailleur**, je veux **créer, consulter, modifier et clôturer un bail liant un bien à un locataire** afin de **formaliser la relation locative avec les conditions financières et les dates, et débloquer la génération des quittances**.

## Context & motivation
Le bail (`lease`) est l'entité pivot qui unit un bien et un locataire avec des conditions contractuelles (loyer, charges, durée). Sans bail actif, il est impossible d'enregistrer un paiement (FEAT-005 dans le backlog original) ni de générer une quittance (FEAT-006). C'est le dernier maillon de la chaîne fondationnelle avant les fonctionnalités financières.

## Acceptance criteria (Gherkin)

**Liste des baux**
- **Given** un propriétaire authentifié navigue vers `/leases`
  **When** la page se charge
  **Then** seuls ses propres baux sont affichés (filtre `landlord_id`), avec les informations synthétiques : nom du bien, nom du locataire, loyer CC, statut (Actif / Terminé), date de début.

- **Given** le propriétaire n'a aucun bail
  **When** la liste se charge
  **Then** un état vide "Aucun bail enregistré" avec un bouton "Créer un bail" est affiché.

**Création d'un bail**
- **Given** le propriétaire clique sur "Créer un bail"
  **When** le formulaire s'ouvre
  **Then** les champs suivants sont présents :
  - Bien (dropdown de ses `properties` actives, obligatoire)
  - Locataire (dropdown de ses `tenants` actifs, obligatoire)
  - Loyer hors charges en euros (obligatoire, numérique positif, format `1 234,56 €`)
  - Charges mensuelles en euros (obligatoire, 0 accepté)
  - Date de début (obligatoire, date picker, format DD/MM/YYYY)
  - Date de fin (optionnel — vide = bail reconductible tacitement)

- **Given** le propriétaire remplit le formulaire valide et soumet
  **When** l'insertion Supabase réussit (montants convertis en centimes côté client avant envoi)
  **Then** le bail apparaît dans la liste avec le statut "Actif", un toast "Bail créé" s'affiche.

- **Given** un bien est déjà lié à un bail actif (`leases.status = 'active'`)
  **When** le propriétaire tente de créer un second bail actif sur ce même bien
  **Then** un avertissement est affiché ("Ce bien a déjà un bail actif. Voulez-vous continuer ?") — la création reste possible après confirmation (cas copropriété / erreur de saisie).

- **Given** la date de fin est antérieure à la date de début
  **When** la validation côté client s'exécute
  **Then** un message d'erreur "La date de fin doit être postérieure à la date de début" s'affiche et aucun appel Supabase n'est effectué.

- **Given** le loyer ou les charges sont négatifs ou non-numériques
  **When** la validation côté client s'exécute
  **Then** un message d'erreur inline s'affiche sur le champ concerné.

**Fiche bail (lecture)**
- **Given** le propriétaire clique sur un bail dans la liste
  **When** il arrive sur `/leases/:id`
  **Then** toutes les informations sont affichées : bien lié (avec lien vers `/properties/:id`), locataire lié (avec lien vers `/tenants/:id`), loyer HC, charges, loyer CC, dates, statut, et la liste des paiements associés (vide si FEAT-005/006 pas encore implémentés).

- **Given** un propriétaire A tente d'accéder à `/leases/:id` d'un bail appartenant au propriétaire B
  **When** la requête Supabase est exécutée
  **Then** la page affiche "Bail introuvable" (RLS retourne 0 ligne).

**Modification d'un bail**
- **Given** le propriétaire est sur la fiche d'un bail actif et clique sur "Modifier"
  **When** le formulaire d'édition s'ouvre
  **Then** tous les champs sont modifiables (y compris loyer et charges — l'historique des paiements est conservé indépendamment).

- **Given** le propriétaire modifie des champs valides et soumet
  **When** l'UPDATE Supabase réussit
  **Then** la fiche affiche les nouvelles valeurs, `updated_at` est mis à jour, un toast "Modifications enregistrées" s'affiche.

**Clôture d'un bail**
- **Given** le propriétaire clique sur "Clôturer le bail" sur la fiche d'un bail actif
  **When** une dialog de confirmation s'affiche avec une date de fin effective (date picker, pré-remplie avec aujourd'hui)
  **Then** après confirmation, `status = 'terminated'`, `end_date = date saisie`, `updated_at = now()`. Le bail reste visible dans la liste avec le statut "Terminé" et `deleted_at` reste NULL.

- **Given** un bail est clôturé
  **When** le propriétaire tente de créer un paiement sur ce bail
  **Then** l'action est bloquée avec le message "Ce bail est clôturé."

**Affichage des montants**
- **Given** les montants sont stockés en centimes dans Supabase
  **When** l'UI affiche le loyer ou les charges
  **Then** les montants sont affichés au format `1 234,56 €` (espace insécable, virgule décimale, € à droite, locale fr_FR).

## Out of scope
- Indexation des loyers (IRL) — P1
- Gestion des dépôts de garantie — P1
- Renouvellement automatique avec notification — P1
- Avenants / modifications historisées — P1
- Baux multi-locataires (colocation) — P1
- Import depuis PDF / document scanné — P2
- Hard-delete (jamais)

## Dependencies
- Tables Supabase : `leases`, `properties`, `tenants`, `landlords` (toutes FEAT-002)
- Features bloquantes : FEAT-001 (auth), FEAT-002 (schéma + RLS), FEAT-003 (properties doivent exister), FEAT-004 (tenants doivent exister)
- Routes Flutter : `/leases` (liste), `/leases/new` (création), `/leases/:id` (fiche + édition)

## Legal / compliance notes
- **Loi du 6 juillet 1989** : les champs `rent_amount_cents` et `charges_amount_cents` alimenteront les quittances (FEAT-006). Leurs valeurs doivent correspondre exactement aux montants figurant dans le bail signé.
- **Conservation 5 ans** : un bail ne peut jamais être hard-deleted. La clôture (statut `terminated`) et le soft-delete (`deleted_at`) sont les deux seules opérations de "suppression" autorisées.
- **Format montants** : les centimes évitent les erreurs d'arrondi sur les montants légaux. La conversion `euros ↔ centimes` se fait côté client, jamais côté base (pas de `numeric` avec virgule flottante pour les montants financiers).
- **Bail reconductible** : `end_date NULL` est une situation légale courante (bail d'habitation à durée indéterminée) — explicitement supportée.

## Priority
P0 (MVP)

## Estimated effort
M (1-3 jours)

## Definition of Done
- [ ] Code formaté, `flutter analyze` clean
- [ ] RLS testée : un propriétaire B ne peut ni lire ni modifier les baux du propriétaire A
- [ ] Tests widget : formulaire création (validation dates, montants), avertissement bail actif existant, clôture
- [ ] Conversion centimes ↔ euros testée (arrondi, cas limites)
- [ ] `code-reviewer` approuvé, `security-auditor` approuvé
- [ ] Migration Supabase N/A (table créée dans FEAT-002)
- [ ] Routes `/leases`, `/leases/new`, `/leases/:id` fonctionnelles
- [ ] Déployé sur Firebase Hosting (env dev)
