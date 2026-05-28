# [FEAT-002] Modèle de données & RLS

## User story
En tant que **développeur / architecte du projet**, je veux **que le schéma Postgres fondamental soit en place avec RLS activée** afin de **garantir que chaque propriétaire ne peut accéder qu'à ses propres données dès la première ligne de code métier**.

## Context & motivation
Story fondationnelle. Toutes les features CRUD (FEAT-003, 004, 005) dépendent de ce schéma. Créer les tables correctement dès le début — avec soft-delete, timestamps, et politiques RLS — évite des migrations correctrices coûteuses. La RLS est un garde-fou non négociable : sans elle, une faille dans la logique Flutter suffit à exposer les données de tous les propriétaires.

## Acceptance criteria (Gherkin)

**Tables créées**
- **Given** la migration est appliquée
  **When** on inspecte le schéma `public` (et `dev`)
  **Then** les tables suivantes existent avec les colonnes listées ci-dessous :
  - `landlords` : `id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE NO ACTION` _(1-1 partagé, aligné FEAT-001 — cf. décisions d'arbitrage 2026-05-28)_, `full_name text`, `email text`, `phone text`, `address text`, `created_at timestamptz DEFAULT now()`, `updated_at timestamptz DEFAULT now()`, `deleted_at timestamptz NULL`
  - `properties` : `id uuid PK DEFAULT gen_random_uuid()`, `landlord_id uuid FK landlords(id) NOT NULL`, `name text NOT NULL`, `address text NOT NULL`, `type text NOT NULL` (appartement, maison, studio, autre), `surface_m2 numeric(6,2)`, `created_at timestamptz DEFAULT now()`, `updated_at timestamptz DEFAULT now()`, `deleted_at timestamptz NULL`
  - `tenants` : `id uuid PK DEFAULT gen_random_uuid()`, `landlord_id uuid FK landlords(id) NOT NULL`, `first_name text NOT NULL`, `last_name text NOT NULL`, `email text NOT NULL`, `phone text`, `created_at timestamptz DEFAULT now()`, `updated_at timestamptz DEFAULT now()`, `deleted_at timestamptz NULL`
  - `leases` : `id uuid PK DEFAULT gen_random_uuid()`, `landlord_id uuid FK landlords(id) NOT NULL`, `property_id uuid FK properties(id) NOT NULL`, `tenant_id uuid FK tenants(id) NOT NULL`, `rent_amount_cents integer NOT NULL` (centimes d'euro, pas de virgule flottante), `charges_amount_cents integer NOT NULL DEFAULT 0`, `start_date date NOT NULL`, `end_date date NULL` (NULL = bail reconductible), `status text NOT NULL DEFAULT 'active'` (active, terminated, archived), `created_at timestamptz DEFAULT now()`, `updated_at timestamptz DEFAULT now()`, `deleted_at timestamptz NULL`

**Timestamps automatiques**
- **Given** un enregistrement est inséré ou mis à jour dans n'importe laquelle des tables ci-dessus
  **When** l'opération se termine
  **Then** `updated_at` est automatiquement mis à jour via un trigger Postgres.

**RLS activée et vérifiée**
- **Given** la migration est appliquée
  **When** on exécute `dev.assert_rls_both_schemas('landlords')` (et idem pour les 3 autres tables)
  **Then** aucune exception n'est levée (RLS activée sur `public` et `dev`).

- **Given** un utilisateur A authentifié tente de lire les `properties` de l'utilisateur B
  **When** la requête est exécutée avec le JWT de l'utilisateur A
  **Then** zéro ligne est retournée.

- **Given** un utilisateur A tente d'insérer une `property` avec un `landlord_id` appartenant à l'utilisateur B
  **When** la requête est exécutée
  **Then** une erreur RLS est retournée (violation de politique).

**Politiques RLS attendues (par table)** — _aligné Option A + protection soft-delete via trigger BEFORE UPDATE_
- `landlords` : SELECT/UPDATE uniquement si `id = auth.uid() AND deleted_at IS NULL`. **AUCUNE policy INSERT côté client** (provisioning réservé au trigger `handle_new_user` SECURITY DEFINER). **AUCUNE policy DELETE** (soft-delete via RPC `soft_delete_*` SECURITY DEFINER).
- `properties`, `tenants`, `leases` : SELECT/INSERT/UPDATE uniquement si `landlord_id = auth.uid() AND deleted_at IS NULL` (filtrage soft-delete inclus dans `USING`). AUCUNE policy DELETE (soft-delete via RPC).
- Trigger `BEFORE UPDATE` sur les 4 tables × 2 schémas qui empêche le client de modifier `deleted_at`, `created_at`, et neutralise `updated_at` (toujours `now()`).

**Soft-delete**
- **Given** un enregistrement est "supprimé" via l'application
  **When** on inspecte la base de données
  **Then** la ligne existe toujours avec `deleted_at = now()`, elle n'est pas effacée physiquement.

- **Given** les politiques RLS sont appliquées
  **When** un utilisateur authentifié lit ses données
  **Then** les enregistrements avec `deleted_at IS NOT NULL` sont exclus des résultats (filtrage dans les policies ou les vues).

**Trigger création landlord**
- **Given** un nouvel utilisateur se connecte via magic link (FEAT-001)
  **When** Supabase Auth crée l'entrée dans `auth.users`
  **Then** un enregistrement correspondant est créé automatiquement dans `landlords` (via trigger `after insert on auth.users`), avec `email` copié et `full_name` vide (à compléter dans les paramètres).

**Migration duale (multi-env)**
- **Given** la migration est exécutée
  **When** on vérifie les schémas
  **Then** toutes les tables, triggers et politiques RLS sont identiques dans `public` (PROD) et `dev` (DEV).

## Out of scope
- Tables `payments` et `receipts` (FEAT-005 / FEAT-006)
- Bucket Supabase Storage (FEAT-008)
- Données de seed / fixtures de test
- Colonnes métier avancées (ex: `deposit_amount`, `notice_period`) — P1

## Dependencies
- Tables Supabase : création initiale dans cette story
- Features bloquantes : FEAT-001 (le trigger `landlords` dépend de `auth.users` géré par Supabase)
- Infrastructure : schéma `dev` déjà créé (migration `00000000000000_init_dev_schema.sql`)

## Legal / compliance notes
- **RGPD / rétention 5 ans** : le soft-delete (`deleted_at`) sur toutes les tables est obligatoire pour conserver les baux et données fiscales 5 ans même après "suppression" par le propriétaire. Voir `docs/LEGAL.md`.
- **Montants en centimes** : `rent_amount_cents` et `charges_amount_cents` stockés en entiers (centimes) pour éviter les erreurs d'arrondi flottant — l'affichage en `1 234,56 €` est la responsabilité de la couche UI.
- Données personnelles (`email`, `phone` dans `tenants`) : couvertes par la politique de confidentialité, effaçables à la demande hors obligation fiscale.

## Décisions d'arbitrage (2026-05-28)
- **PK `landlords`** : Option A retenue → `id = auth.users.id` (relation 1-1 partagée, cohérent avec FEAT-001 déjà déployé staging). Le multi-tenant (SCI, mandataire) sera adressé P2 via une table de jointure, pas via la PK.
- **FK `landlords.id → auth.users(id)`** : `ON DELETE NO ACTION` (remplace le `CASCADE` de FEAT-001). La suppression d'un compte auth échouera si une ligne `landlords` existe → l'effacement RGPD passera par une Edge Function dédiée (P1) qui anonymise plutôt que d'effacer, conforme à la rétention 5 ans.
- **Soft-delete** : filtrage via `deleted_at IS NULL` directement dans les `USING` des policies RLS (pas de vues `*_visible` séparées). Plus simple, moins de duplication.
- **Protection colonnes** : trigger `BEFORE UPDATE` sur les 4 tables × 2 schémas qui empêche le client de modifier `deleted_at` et `created_at`, neutralise `updated_at`. Le soft-delete passe par des RPC SECURITY DEFINER (`soft_delete_landlord`, etc.).
- **Modèles Flutter** : aucun en FEAT-002 (story purement backend). Les modèles `Landlord`/`Property`/`Tenant`/`Lease` (freezed) seront créés au fil des features CRUD (FEAT-003/004/005), au plus proche de leur usage.
- **Migration data staging** : aucune nécessaire (Option A conserve les lignes `landlords` créées en staging via FEAT-001). La FK `CASCADE` → `NO ACTION` est un changement de contrainte qui se fait via `ALTER TABLE … DROP CONSTRAINT … ADD CONSTRAINT …` sans toucher aux données.

## Priority
P0 (MVP)

## Estimated effort
M (1-3 jours)

## Definition of Done
- [ ] Code formaté, `flutter analyze` clean (côté Dart si modèles générés)
- [ ] RLS testée manuellement (cross-user via Supabase Studio ou psql)
- [ ] `dev.assert_rls_both_schemas()` passe sur les 4 tables
- [ ] `security-auditor` approuvé (vérifie que chaque table a une policy et que RLS est ON)
- [ ] Migration appliquée sur `dev` et `public`
- [ ] `docs/state/SCHEMA.md` mis à jour par `state-keeper` après merge
