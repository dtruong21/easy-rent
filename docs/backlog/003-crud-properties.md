# [FEAT-003] CRUD biens immobiliers

## User story
En tant que **propriétaire bailleur**, je veux **créer, consulter, modifier et archiver mes biens immobiliers** afin de **disposer d'un registre à jour de mon parc locatif sur lequel je peux ensuite affecter des locataires et des baux**.

## Context & motivation
Le bien immobilier (`property`) est l'entité centrale autour de laquelle s'organise toute la gestion locative. Sans cette feature, il est impossible de créer un bail (FEAT-005). L'archivage (soft-delete) remplace la suppression définitive pour conserver la traçabilité des baux passés.

## Acceptance criteria (Gherkin)

**Liste des biens**
- **Given** un propriétaire authentifié navigue vers `/properties`
  **When** la page se charge
  **Then** seuls ses propres biens avec `deleted_at IS NULL` sont affichés (liste ou cards), triés par `created_at DESC`.

- **Given** le propriétaire n'a aucun bien
  **When** la liste se charge
  **Then** un état vide "Aucun bien enregistré" avec un bouton "Ajouter un bien" est affiché.

**Création d'un bien**
- **Given** le propriétaire clique sur "Ajouter un bien"
  **When** le formulaire de création s'ouvre
  **Then** les champs suivants sont présents : Nom du bien (obligatoire), Adresse complète (obligatoire), Type (dropdown : Appartement / Maison / Studio / Autre, obligatoire), Surface en m² (optionnel, numérique positif).

- **Given** le propriétaire remplit le formulaire valide et soumet
  **When** l'insertion Supabase réussit
  **Then** le nouveau bien apparaît dans la liste, un toast "Bien créé" s'affiche, et l'utilisateur est redirigé vers la liste `/properties`.

- **Given** le champ "Nom" ou "Adresse" est vide à la soumission
  **When** la validation côté client s'exécute
  **Then** des messages d'erreur inline s'affichent sur les champs concernés et aucun appel Supabase n'est effectué.

**Fiche bien (lecture)**
- **Given** le propriétaire clique sur un bien dans la liste
  **When** il arrive sur `/properties/:id`
  **Then** toutes les informations du bien sont affichées (nom, adresse, type, surface), ainsi que la liste des baux actifs liés à ce bien.

- **Given** un propriétaire A tente d'accéder à `/properties/:id` d'un bien appartenant au propriétaire B
  **When** la requête Supabase est exécutée
  **Then** la page affiche une erreur "Bien introuvable" (RLS retourne 0 ligne — pas de fuite d'information).

**Modification d'un bien**
- **Given** le propriétaire est sur la fiche d'un bien et clique sur "Modifier"
  **When** le formulaire d'édition s'ouvre
  **Then** les champs sont pré-remplis avec les valeurs actuelles.

- **Given** le propriétaire modifie des champs valides et soumet
  **When** l'UPDATE Supabase réussit
  **Then** la fiche affiche les nouvelles valeurs, `updated_at` est mis à jour, un toast "Modifications enregistrées" s'affiche.

**Archivage d'un bien**
- **Given** le propriétaire clique sur "Archiver" sur la fiche d'un bien
  **When** une dialog de confirmation s'affiche ("Archiver ce bien ? Les baux actifs liés seront conservés.")
  **Then** après confirmation, `deleted_at = now()` est positionné, le bien disparaît de la liste principale.

- **Given** un bien est archivé
  **When** le propriétaire navigue vers la liste
  **Then** le bien archivé n'apparaît pas (sauf si un filtre "Afficher archivés" est activé — optionnel en V1).

- **Given** un bien a un bail actif (`leases.status = 'active'`)
  **When** le propriétaire tente de l'archiver
  **Then** un avertissement est affiché ("Ce bien a un bail actif. Êtes-vous sûr ?") — l'archivage reste possible après confirmation explicite.

## Out of scope
- Upload de photos du bien (P1)
- Géolocalisation / carte (P2)
- Calcul de rentabilité (P1)
- Import CSV de biens (P2)
- Hard-delete (jamais — rétention légale)

## Dependencies
- Tables Supabase : `properties` (FEAT-002), `leases` (FEAT-005 pour l'avertissement bail actif — peut être simplifié en V1)
- Features bloquantes : FEAT-001 (auth), FEAT-002 (schéma + RLS)
- Routes Flutter : `/properties` (liste), `/properties/new` (création), `/properties/:id` (fiche + édition)

## Legal / compliance notes
- **Soft-delete obligatoire** : ne jamais hard-delete une `property` liée à un bail — les quittances doivent rester traçables 5 ans. Voir `docs/LEGAL.md`.
- Adresse du bien est une donnée nécessaire pour les quittances légales (loi 6 juillet 1989, art. 21) — le champ adresse est donc obligatoire.

## Priority
P0 (MVP)

## Estimated effort
M (1-3 jours)

## Definition of Done
- [ ] Code formaté, `flutter analyze` clean
- [ ] RLS testée : un propriétaire B ne peut ni lire ni modifier les biens du propriétaire A
- [ ] Tests widget : formulaire création (validation), liste vide, archivage
- [ ] `code-reviewer` approuvé, `security-auditor` approuvé
- [ ] Migration Supabase N/A (table créée dans FEAT-002)
- [ ] Routes `/properties`, `/properties/new`, `/properties/:id` fonctionnelles
- [ ] Déployé sur Firebase Hosting (env dev)
