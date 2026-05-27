# [FEAT-004] CRUD locataires

## User story
En tant que **propriétaire bailleur**, je veux **créer, consulter, modifier et archiver les fiches de mes locataires** afin de **disposer d'un annuaire centralisé que je peux associer à mes baux**.

## Context & motivation
Le locataire (`tenant`) est l'autre entité centrale d'un bail. Sa fiche contient les informations de contact nécessaires pour l'envoi des quittances (email) et pour les obligations légales (identification dans les documents). L'archivage remplace la suppression pour respecter la rétention des données liées aux baux passés.

## Acceptance criteria (Gherkin)

**Liste des locataires**
- **Given** un propriétaire authentifié navigue vers `/tenants`
  **When** la page se charge
  **Then** seuls ses propres locataires avec `deleted_at IS NULL` sont affichés, triés par `last_name ASC`.

- **Given** le propriétaire n'a aucun locataire
  **When** la liste se charge
  **Then** un état vide "Aucun locataire enregistré" avec un bouton "Ajouter un locataire" est affiché.

**Création d'un locataire**
- **Given** le propriétaire clique sur "Ajouter un locataire"
  **When** le formulaire de création s'ouvre
  **Then** les champs suivants sont présents : Prénom (obligatoire), Nom (obligatoire), Email (obligatoire, format email), Téléphone (optionnel).

- **Given** le propriétaire remplit le formulaire valide et soumet
  **When** l'insertion Supabase réussit
  **Then** le nouveau locataire apparaît dans la liste, un toast "Locataire créé" s'affiche, et l'utilisateur est redirigé vers la liste `/tenants`.

- **Given** le champ "Email" contient une valeur non conforme au format email
  **When** la validation côté client s'exécute à la soumission
  **Then** un message d'erreur inline s'affiche ("Adresse email invalide") et aucun appel Supabase n'est effectué.

- **Given** les champs "Prénom" ou "Nom" sont vides
  **When** la validation côté client s'exécute
  **Then** des messages d'erreur inline s'affichent et aucun appel Supabase n'est effectué.

**Fiche locataire (lecture)**
- **Given** le propriétaire clique sur un locataire dans la liste
  **When** il arrive sur `/tenants/:id`
  **Then** toutes les informations sont affichées (prénom, nom, email, téléphone) ainsi que la liste des baux liés à ce locataire (actifs et terminés).

- **Given** un propriétaire A tente d'accéder à `/tenants/:id` d'un locataire appartenant au propriétaire B
  **When** la requête Supabase est exécutée
  **Then** la page affiche "Locataire introuvable" (RLS retourne 0 ligne).

**Modification d'un locataire**
- **Given** le propriétaire est sur la fiche d'un locataire et clique sur "Modifier"
  **When** le formulaire d'édition s'ouvre
  **Then** les champs sont pré-remplis avec les valeurs actuelles.

- **Given** le propriétaire modifie des champs valides et soumet
  **When** l'UPDATE Supabase réussit
  **Then** la fiche affiche les nouvelles valeurs, `updated_at` est mis à jour, un toast "Modifications enregistrées" s'affiche.

**Archivage d'un locataire**
- **Given** le propriétaire clique sur "Archiver" sur la fiche d'un locataire
  **When** une dialog de confirmation s'affiche
  **Then** après confirmation, `deleted_at = now()` est positionné et le locataire disparaît de la liste principale.

- **Given** un locataire a un bail actif (`leases.status = 'active'`)
  **When** le propriétaire tente de l'archiver
  **Then** un avertissement est affiché ("Ce locataire a un bail actif. Êtes-vous sûr ?") — l'archivage reste possible après confirmation explicite.

**Recherche / filtre (optionnel V1)**
- **Given** la liste contient plusieurs locataires
  **When** le propriétaire saisit un terme dans le champ de recherche
  **Then** la liste est filtrée en temps réel sur `first_name` et `last_name` (recherche côté client sur les données déjà chargées).

## Out of scope
- Gestion des co-locataires (plusieurs locataires par bail) — P1
- Upload de pièces justificatives d'identité dans cette story (FEAT-008)
- Dossier de candidature / scoring — P2
- Import CSV de locataires — P2
- Hard-delete (jamais — rétention légale)
- Envoi d'email depuis la fiche locataire (hors quittance) — P1

## Dependencies
- Tables Supabase : `tenants` (FEAT-002), `leases` (FEAT-005 pour l'affichage des baux liés)
- Features bloquantes : FEAT-001 (auth), FEAT-002 (schéma + RLS)
- Routes Flutter : `/tenants` (liste), `/tenants/new` (création), `/tenants/:id` (fiche + édition)

## Legal / compliance notes
- **RGPD** : les données personnelles du locataire (nom, email, téléphone) sont traitées dans le cadre de la relation contractuelle (base légale : exécution du contrat). Le propriétaire est responsable de traitement secondaire pour ces données.
- **Droit à l'effacement** : si un locataire demande la suppression de ses données, le propriétaire doit pouvoir effacer les informations personnelles tout en conservant les documents légaux (baux, quittances) 5 ans. Dans cette version V1, l'archivage suffit — une feature d'anonymisation est P1.
- **Email locataire** : utilisé pour l'envoi des quittances (FEAT-007) — champ obligatoire.
- **Conservation** : les données du locataire liées à un bail terminé doivent être conservées 5 ans minimum (prescription civile). Soft-delete obligatoire, jamais de hard-delete sur un locataire ayant eu un bail.

## Priority
P0 (MVP)

## Estimated effort
M (1-3 jours)

## Definition of Done
- [ ] Code formaté, `flutter analyze` clean
- [ ] RLS testée : un propriétaire B ne peut ni lire ni modifier les locataires du propriétaire A
- [ ] Tests widget : formulaire création (validation email, champs obligatoires), liste vide, archivage
- [ ] `code-reviewer` approuvé, `security-auditor` approuvé
- [ ] Migration Supabase N/A (table créée dans FEAT-002)
- [ ] Routes `/tenants`, `/tenants/new`, `/tenants/:id` fonctionnelles
- [ ] Déployé sur Firebase Hosting (env dev)
