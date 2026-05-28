# Plan — [FEAT-002] Modèle de données & RLS

> Source : [`docs/backlog/002-data-model-rls.md`](../backlog/002-data-model-rls.md)
> Auteur : `architect` — 2026-05-28
> État référence : `docs/state/SCHEMA.md` (post FEAT-001)

---

## Summary

FEAT-002 pose le socle Postgres des features CRUD (FEAT-003/004/005) :
extension de `landlords`, création de `properties`, `tenants`, `leases` avec
RLS, soft-delete protégé par trigger, `updated_at` automatique. Le plan tranche
sur trois questions critiques : la forme de la PK de `landlords` (héritage
FEAT-001), la politique `ON DELETE` vers `auth.users` vs rétention 5 ans, et la
stratégie de filtrage du soft-delete (USING vs vues). Aucune modification
Flutter dans cette story — les modèles `freezed` resteront pour FEAT-003+.

---

## 0. Questions critiques (à arbitrer AVANT toute migration)

### Q1 — PK de `landlords` : id partagé avec auth.users ou id séparé + user_id ? **(CRITIQUE)**

**Recommandation : Option A — garder le design FEAT-001 (`id = auth.users.id`, 1-1) et amender la story.**

Arguments :

1. **Cohérence avec l'existant déployé.** FEAT-001 est mergée, staging tourne avec
   ce design. Toutes les policies actuelles (`id = auth.uid()`), le trigger
   `handle_new_user`, et la doc état (`docs/state/SCHEMA.md`) reposent dessus.
2. **Aucune valeur métier ajoutée par le découplage.** Le couple `(id PK, user_id UNIQUE NOT NULL FK)`
   n'apporterait rien tant que la relation reste 1-1. Le coût (migration de
   données, refonte trigger, refonte RLS, double sous-requête sur les enfants
   `landlord_id IN (SELECT id FROM landlords WHERE user_id = auth.uid())`) est
   réel ; le bénéfice est nul.
3. **Simplicité RLS sur les enfants.** Avec id = auth.uid(), les policies enfants
   deviennent `landlord_id = auth.uid()` (zéro sous-requête, plan d'exécution
   trivial). Avec un user_id séparé, chaque check RLS force une sous-requête
   indexée vers `landlords` — surcoût pour zéro gain.
4. **Le seul cas où le découplage serait utile** = multi-utilisateurs par landlord
   (mandataire, comptable partagé). C'est P2 selon `ROADMAP.md`. Quand on y
   arrivera, on créera une table de jointure `landlord_members` (landlord_id,
   user_id, role) sans toucher à la PK.
5. **RGPD / rétention** ne tranche pas la question — peut être résolu avec
   l'Option A en passant juste `ON DELETE CASCADE` → `ON DELETE NO ACTION` (Q2).

Conséquences si Option A retenue :
- ✏️ Amender `docs/backlog/002-data-model-rls.md` : retirer la spec
  "id uuid PK + user_id uuid UNIQUE NOT NULL FK auth.users". Remplacer par
  "id uuid PK FK auth.users(id) ON DELETE NO ACTION" (cf. Q2).
- ✏️ Amender la spec RLS enfants : `landlord_id = auth.uid()` (au lieu de la
  sous-requête).
- ✅ Migration purement additive : `ALTER TABLE` sur landlords + 3 CREATE TABLE
  pour properties/tenants/leases. Aucune migration de données.

**Décision à confirmer par le product-owner** avant de lancer `supabase-dev`.

### Q2 — `landlords.id REFERENCES auth.users(id) ON DELETE ?`

**Recommandation : `ON DELETE NO ACTION` (= bloque la suppression auth.users tant qu'il existe une ligne landlords non hard-deleted).**

Justification :
- L'obligation fiscale impose 5 ans de rétention sur baux + quittances. Si on
  laisse `CASCADE`, la suppression d'un `auth.users` (par Supabase admin, par
  une Edge Function "delete account" future, ou par un GDPR-eraser) efface
  *physiquement* la ligne landlord + (par cascade) toutes ses properties,
  tenants, leases, payments, receipts. Inacceptable.
- `RESTRICT` et `NO ACTION` ont quasi le même effet ; `NO ACTION` est le
  défaut PG et autorise le report en `DEFERRABLE` si un jour on veut une
  transaction multi-étapes. → `NO ACTION` par défaut.
- Le flux RGPD "droit à l'effacement" passera plus tard par une Edge Function
  (`rgpd-erase-account`) qui (a) anonymise les données obligatoirement
  conservées (anonymisation = `email → tombstone@erased.local`, `phone → NULL`)
  et (b) hard-delete les données non soumises à rétention (FEAT P1). Tant que
  cette fonction n'existe pas, on laisse simplement la ligne `landlords` en
  place et on déconseille la suppression de comptes via Studio.

**À confirmer par le product-owner.**

### Q3 — Filtrage soft-delete : `deleted_at IS NULL` dans les USING RLS ou via vues `*_visible` ?

**Recommandation : inclure `deleted_at IS NULL` dans les `USING` des policies SELECT/UPDATE.**

Arguments :
- C'est ce que FEAT-001 fait déjà sur `landlords`. Cohérence.
- Une vue `*_visible` ajoute une couche dans le path SQL pour zéro gain de
  sécurité (les vues ne portent pas leur propre RLS — elles héritent de celles
  des tables sous-jacentes uniquement si `security_invoker` est posé).
- L'admin (via service_role) doit pouvoir voir les lignes soft-deleted pour
  audit / restauration → policies client = `deleted_at IS NULL`, service_role
  bypass RLS naturellement.
- Coût : chaque INSERT pose `deleted_at = NULL` (défaut), chaque "lecteur
  client" est protégé naturellement. Aucune réécriture de requête nécessaire.

**Pas de blocage utilisateur** ici — c'est un choix d'implémentation. Mentionné
pour transparence.

### Q4 — Création des modèles Flutter (`freezed` Landlord/Property/...) en FEAT-002 ?

**Recommandation : NON. Pas de code Flutter en FEAT-002.**

Arguments :
- Principe "don't add features beyond what the task requires".
- Les CRUD FEAT-003/004/005 produiront les modèles avec le besoin réel devant
  les yeux (formulaires, validators, mappers). Anticiper = sur-engineering.
- L'extension de `landlords` (full_name, phone, address) ne motive pas à elle
  seule un modèle Dart — la lecture du landlord courant se fera via un provider
  Riverpod simple (P1 lorsque FEAT-003 démarre).

→ FEAT-002 = migration SQL + tests RLS. Point.

---

## 1. Découpage en migrations Postgres

Une seule migration, transactionnelle, idempotente sur les éléments réutilisés
(`CREATE OR REPLACE FUNCTION`, `DROP TRIGGER IF EXISTS`).

| # | Fichier | Contenu |
|---|---|---|
| 1 | `supabase/migrations/<TS>_feat002_data_model_rls.sql` | Tout FEAT-002 |

Pourquoi une seule migration :
- Les 4 tables sont interdépendantes (FK leases→properties+tenants).
- Atomicité : si une CHECK constraint pose problème, tout rollback.
- La dette FK CASCADE→NO ACTION sur `landlords.id` se règle dans la même
  transaction (ALTER TABLE DROP CONSTRAINT + ADD CONSTRAINT).

Structure interne (commentaires SQL en français) :

```
-- Section 0 : helpers (fonction set_updated_at déjà existante → no-op si présente)
-- Section 1 : ALTER landlords (drop CASCADE, add NO ACTION, add full_name/phone/address)
-- Section 2 : CREATE TABLE properties (public + dev)
-- Section 3 : CREATE TABLE tenants    (public + dev)
-- Section 4 : CREATE TABLE leases     (public + dev)
-- Section 5 : Triggers updated_at + prevent_protected_columns_change (4 tables × 2 schémas)
-- Section 6 : RLS policies (4 tables × 2 schémas)
-- Section 7 : Indexes (FK + filtrage soft-delete partiel)
-- Section 8 : assert_rls_both_schemas() pour les 4 tables (échoue la migration si KO)
```

---

## 2. Schéma final détaillé

### 2.1 `landlords` (étendu — ALTER TABLE)

| Colonne | Type | Contraintes | Source |
|---|---|---|---|
| `id` | `uuid` | PK, FK → `auth.users(id)` **`ON DELETE NO ACTION`** | FEAT-001 (FK modifiée) |
| `email` | `text` | NOT NULL | FEAT-001 |
| `full_name` | `text` | NULL (à compléter via formulaire paramètres) | **NOUVEAU** |
| `phone` | `text` | NULL | **NOUVEAU** |
| `address` | `text` | NULL | **NOUVEAU** |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() | FEAT-001 |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now(), maintenu par trigger | FEAT-001 |
| `deleted_at` | `timestamptz` | NULL — protégé par trigger | FEAT-001 (protection ajoutée) |

DDL clé :
```sql
ALTER TABLE public.landlords DROP CONSTRAINT landlords_id_fkey;
ALTER TABLE public.landlords
  ADD CONSTRAINT landlords_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE NO ACTION;

ALTER TABLE public.landlords
  ADD COLUMN full_name text,
  ADD COLUMN phone     text,
  ADD COLUMN address   text;
-- (idem sur dev.landlords avec dev_landlords_id_fkey)
```

### 2.2 `properties` (NOUVELLE)

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PK DEFAULT `gen_random_uuid()` |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` **`ON DELETE RESTRICT`** |
| `name` | `text` | NOT NULL, CHECK `length(trim(name)) > 0` |
| `address` | `text` | NOT NULL, CHECK `length(trim(address)) > 0` |
| `type` | `text` | NOT NULL, CHECK `type IN ('appartement','maison','studio','autre')` |
| `surface_m2` | `numeric(6,2)` | NULL, CHECK `surface_m2 IS NULL OR surface_m2 > 0` |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() (trigger) |
| `deleted_at` | `timestamptz` | NULL (protégé par trigger) |

`ON DELETE RESTRICT` sur `landlord_id` : aligné Q2 — un landlord ne peut pas
être hard-deleted s'il a des properties (cohérence rétention).

### 2.3 `tenants` (NOUVELLE)

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PK DEFAULT `gen_random_uuid()` |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` **`ON DELETE RESTRICT`** |
| `first_name` | `text` | NOT NULL, CHECK `length(trim(first_name)) > 0` |
| `last_name` | `text` | NOT NULL, CHECK `length(trim(last_name)) > 0` |
| `email` | `text` | NOT NULL, CHECK `email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'` (regex minimaliste, on durcira côté Flutter) |
| `phone` | `text` | NULL |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() (trigger) |
| `deleted_at` | `timestamptz` | NULL (protégé par trigger) |

### 2.4 `leases` (NOUVELLE)

| Colonne | Type | Contraintes |
|---|---|---|
| `id` | `uuid` | PK DEFAULT `gen_random_uuid()` |
| `landlord_id` | `uuid` | NOT NULL, FK → `landlords(id)` ON DELETE RESTRICT |
| `property_id` | `uuid` | NOT NULL, FK → `properties(id)` ON DELETE RESTRICT |
| `tenant_id` | `uuid` | NOT NULL, FK → `tenants(id)` ON DELETE RESTRICT |
| `rent_amount_cents` | `integer` | NOT NULL, CHECK `rent_amount_cents > 0` |
| `charges_amount_cents` | `integer` | NOT NULL DEFAULT 0, CHECK `charges_amount_cents >= 0` |
| `start_date` | `date` | NOT NULL |
| `end_date` | `date` | NULL, CHECK `end_date IS NULL OR end_date > start_date` |
| `status` | `text` | NOT NULL DEFAULT `'active'`, CHECK `status IN ('active','terminated','archived')` |
| `created_at` | `timestamptz` | NOT NULL DEFAULT now() |
| `updated_at` | `timestamptz` | NOT NULL DEFAULT now() (trigger) |
| `deleted_at` | `timestamptz` | NULL (protégé par trigger) |

**Cohérence cross-FK** : on doit garantir que `property_id.landlord_id` ==
`tenant_id.landlord_id` == `leases.landlord_id`. Deux approches :
- (a) **CHECK function** trigger BEFORE INSERT/UPDATE — préférable.
- (b) Composite FK : non disponible directement, complexifie le schéma.

**Recommandation : trigger `assert_lease_ownership_consistency`** (cf. §4).
C'est un garde-fou contre une faille RLS (si jamais on faisait sauter une
policy par erreur, le trigger reste actif).

### 2.5 Indexes

| Index | Table | Colonne(s) | Justification |
|---|---|---|---|
| `idx_<sch>_properties_landlord_id` | `properties` | `landlord_id` | FK + filtre RLS |
| `idx_<sch>_tenants_landlord_id` | `tenants` | `landlord_id` | FK + filtre RLS |
| `idx_<sch>_leases_landlord_id` | `leases` | `landlord_id` | FK + filtre RLS |
| `idx_<sch>_leases_property_id` | `leases` | `property_id` | jointure FEAT-005 (1 bien → N baux historiques) |
| `idx_<sch>_leases_tenant_id` | `leases` | `tenant_id` | jointure FEAT-005 |
| `idx_<sch>_leases_status_active_partial` | `leases` | `landlord_id` WHERE `status='active' AND deleted_at IS NULL` | dashboard FEAT-010 |

Pas d'index sur `deleted_at` direct : la sélectivité est faible (`IS NULL`
sera ~99% des lignes). En revanche, **index partiel** sur leases pour le
listing dashboard.

---

## 3. Politiques RLS — liste exhaustive

Tableau exhaustif (mêmes policies dans `public` et `dev`).

### 3.1 `landlords` (déjà partiellement en place — FEAT-001)

| Policy | Cmd | USING | WITH CHECK | État |
|---|---|---|---|---|
| `landlord_selects_self` | SELECT | `id = auth.uid() AND deleted_at IS NULL` | — | déjà présente |
| `landlord_updates_self` | UPDATE | `id = auth.uid() AND deleted_at IS NULL` | `id = auth.uid()` | déjà présente |
| _(pas de INSERT)_ | — | — | — | trigger `handle_new_user` SECURITY DEFINER |
| _(pas de DELETE)_ | — | — | — | soft-delete via RPC |

### 3.2 `properties`

| Policy | Cmd | USING | WITH CHECK |
|---|---|---|---|
| `properties_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` | — |
| `properties_insert_own` | INSERT | — | `landlord_id = auth.uid()` |
| `properties_update_own` | UPDATE | `landlord_id = auth.uid() AND deleted_at IS NULL` | `landlord_id = auth.uid()` |
| _(pas de DELETE)_ | — | — | — | soft-delete via RPC |

### 3.3 `tenants`

| Policy | Cmd | USING | WITH CHECK |
|---|---|---|---|
| `tenants_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` | — |
| `tenants_insert_own` | INSERT | — | `landlord_id = auth.uid()` |
| `tenants_update_own` | UPDATE | `landlord_id = auth.uid() AND deleted_at IS NULL` | `landlord_id = auth.uid()` |
| _(pas de DELETE)_ | — | — | — |

### 3.4 `leases`

| Policy | Cmd | USING | WITH CHECK |
|---|---|---|---|
| `leases_select_own` | SELECT | `landlord_id = auth.uid() AND deleted_at IS NULL` | — |
| `leases_insert_own` | INSERT | — | `landlord_id = auth.uid()` |
| `leases_update_own` | UPDATE | `landlord_id = auth.uid() AND deleted_at IS NULL` | `landlord_id = auth.uid()` |
| _(pas de DELETE)_ | — | — | — |

**Note** : pas de policy DELETE sur aucune table → la suppression physique est
impossible côté client. Le hard-delete (cas RGPD) passera par une Edge Function
admin en P1.

---

## 4. Triggers à créer

### 4.1 `set_updated_at()` (générique — déjà existant)

Réutilisé pour `properties`, `tenants`, `leases`. Aucune modification de la
fonction elle-même. On crée 6 triggers (3 tables × 2 schémas) :

```sql
CREATE TRIGGER set_properties_updated_at
  BEFORE UPDATE ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
-- + idem dev.properties, public.tenants, dev.tenants, public.leases, dev.leases
```

### 4.2 `prevent_protected_columns_change()` (NOUVEAU — applicable aux 4 tables)

Empêche la modification client de `deleted_at`, `created_at` et la
réécriture manuelle de `updated_at`. Le client doit forcément utiliser :
- un UPDATE sans toucher ces colonnes (le trigger set_updated_at gère
  `updated_at`),
- ou une RPC SECURITY DEFINER pour le soft-delete.

```sql
CREATE OR REPLACE FUNCTION public.prevent_protected_columns_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Empêche le client de jouer avec deleted_at via UPDATE direct
  IF NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
    RAISE EXCEPTION 'Column deleted_at cannot be modified directly. Use the soft_delete_* RPC.'
      USING ERRCODE = '42501';  -- insufficient_privilege
  END IF;
  -- created_at est immuable
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Column created_at is immutable.'
      USING ERRCODE = '42501';
  END IF;
  -- updated_at sera réécrit par set_updated_at, on neutralise la tentative client
  NEW.updated_at := OLD.updated_at;
  RETURN NEW;
END;
$$;
```

⚠️ **Ordre des triggers** : `prevent_protected_columns_change` doit s'exécuter
**AVANT** `set_updated_at`. Postgres exécute les triggers BEFORE dans l'ordre
alphabétique des noms → préfixer en `01_prevent_protected_columns_change_*`
et `02_set_*_updated_at`. Alternative : un seul trigger combiné — moins
flexible. **Décision : deux triggers nommés `tr_01_…` et `tr_02_…`** pour
garantir l'ordre.

À poser sur les 4 tables × 2 schémas = 8 triggers `prevent_protected_columns_change`.

### 4.3 `assert_lease_ownership_consistency()` (NOUVEAU — leases uniquement)

```sql
CREATE OR REPLACE FUNCTION public.assert_lease_ownership_consistency()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  prop_landlord uuid;
  tnt_landlord  uuid;
BEGIN
  SELECT landlord_id INTO prop_landlord FROM public.properties WHERE id = NEW.property_id;
  SELECT landlord_id INTO tnt_landlord  FROM public.tenants    WHERE id = NEW.tenant_id;

  IF prop_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Lease.property_id does not belong to landlord_id %', NEW.landlord_id
      USING ERRCODE = '23514';  -- check_violation
  END IF;
  IF tnt_landlord IS DISTINCT FROM NEW.landlord_id THEN
    RAISE EXCEPTION 'Lease.tenant_id does not belong to landlord_id %', NEW.landlord_id
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
```

Trigger BEFORE INSERT OR UPDATE sur leases (× 2 schémas). **Attention** : la
fonction lit `public.properties` et `public.tenants` en hard-codé. Pour le
schéma `dev`, on duplique la fonction en `dev.assert_lease_ownership_consistency`
qui lit `dev.properties` / `dev.tenants`. Pas joli mais nécessaire — éviter
les fonctions dynamiques (sécurité + plan d'exécution).

### 4.4 `handle_new_user()` (déjà existant)

**Pas de modification en Option A.** Le trigger continue d'insérer
`(NEW.id, NEW.email)`. Le nouveau champ `full_name` reste NULL (rempli plus
tard par l'utilisateur via UI paramètres en FEAT-003+).

---

## 5. RPC functions SECURITY DEFINER pour soft-delete

Une RPC par table (pas générique — éviter le dynamic SQL).

```sql
CREATE OR REPLACE FUNCTION public.soft_delete_property(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.properties
    SET deleted_at = now()
    WHERE id = p_id
      AND landlord_id = auth.uid()    -- garde-fou : on ne soft-delete que sa propre ligne
      AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Property not found or already deleted' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.soft_delete_property(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.soft_delete_property(uuid) TO authenticated;
```

Signatures attendues (× 2 schémas) :
- `soft_delete_landlord()` — pas de paramètre, supprime `auth.uid()`
- `soft_delete_property(p_id uuid)`
- `soft_delete_tenant(p_id uuid)`
- `soft_delete_lease(p_id uuid)`

⚠️ **Le trigger `prevent_protected_columns_change` bloque l'UPDATE direct**
dans la RPC aussi (SECURITY DEFINER ne bypasse pas les triggers). Donc la RPC
doit utiliser `SET LOCAL session_replication_role = replica;` pour suspendre
les triggers, OU on prévoit un flag de session (`current_setting('app.allow_deleted_at_change', true)`)
que la RPC pose à `'1'` et que le trigger vérifie pour skipper.

**Recommandation : le flag de session** — moins intrusif que `session_replication_role`
(qui désactive **tous** les triggers) :

```sql
-- Dans prevent_protected_columns_change :
IF NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
   AND current_setting('app.allow_deleted_at_change', true) <> '1' THEN
  RAISE EXCEPTION ...;
END IF;

-- Dans la RPC :
PERFORM set_config('app.allow_deleted_at_change', '1', true);  -- local à la transaction
UPDATE ... SET deleted_at = now() ...;
```

**À valider par `security-auditor`** : ce pattern doit être documenté et le
flag ne doit jamais être posé ailleurs que dans les RPC.

---

## 6. Plan de tests RLS

Nouveaux fichiers (en miroir de `rls_landlords.sql`) :

| Fichier | Couvre |
|---|---|
| `supabase/tests/rls_properties.sql` | SELECT/INSERT/UPDATE cross-user, soft-delete invisible, INSERT avec landlord_id différent rejeté |
| `supabase/tests/rls_tenants.sql` | idem properties |
| `supabase/tests/rls_leases.sql` | idem + test cross-ownership (property d'un user A + tenant d'un user B → trigger rejette) |
| `supabase/tests/rls_landlords.sql` (étendu) | Ajout tests : trigger `prevent_protected_columns_change` rejette UPDATE direct de `deleted_at` ; RPC `soft_delete_landlord` fonctionne |

Pattern de chaque fichier (identique à FEAT-001) :
- BEGIN / setup auth.users + ligne landlord / DO blocks `SET LOCAL ROLE authenticated` + `set_config request.jwt.claims` / ROLLBACK.

Tests transversaux à ajouter :
- TEST cohérence leases : un INSERT leases avec `property.landlord_id ≠ leases.landlord_id` est rejeté par le trigger `assert_lease_ownership_consistency`.
- TEST RPC : la RPC `soft_delete_property` d'un User A sur la `property` d'un User B échoue silencieusement (NOT FOUND) — pas de fuite d'info.
- TEST integrity : `dev.assert_rls_both_schemas('properties' | 'tenants' | 'leases')` passe.

---

## 7. Stratégie de migration des données existantes

**Option A retenue → AUCUNE migration de données.**

- Les `landlords` existants en staging gardent leur `id = auth.users.id`.
- `full_name`, `phone`, `address` sont ajoutés en NULL — par définition aucun
  conflit.
- L'ALTER de la FK CASCADE → NO ACTION est instantané (modification de
  catalogue), aucun verrou de table durable.

Si **par accident** Option B était retenue, la stratégie serait :
1. ALTER landlords ADD COLUMN user_id uuid;
2. UPDATE landlords SET user_id = id;
3. ALTER ADD UNIQUE(user_id), ALTER user_id SET NOT NULL;
4. Pour générer un id PK distinct : ALTER id SET DEFAULT gen_random_uuid(),
   UPDATE landlords SET id = gen_random_uuid() — mais ça casserait les FK
   enfants. Trop coûteux. **Confirme l'Option A**.

---

## 8. Documentation à mettre à jour

À faire par `state-keeper` après merge :

- [ ] `docs/state/SCHEMA.md` — ajouter les 3 tables + listes complètes des
      policies + nouveaux triggers et RPC.
- [ ] `docs/backlog/002-data-model-rls.md` — amender la spec PK landlords si
      Option A retenue (cf. Q1).
- [ ] `docs/BACKLOG.md` — déplacer les dettes "À traiter en FEAT-002" de la
      section "À traiter" vers "Résolu", ajouter la dette résiduelle "RGPD
      self-service P1" qui reste ouverte.
- [ ] `docs/state/FUNCTIONS.md` — documenter les 4 RPC `soft_delete_*`.

---

## 9. Séquencement (qui fait quoi)

1. **product-owner** : valide Q1 (Option A) et Q2 (`NO ACTION`). Bloquant.
2. **supabase-dev** :
   - Écrit la migration `supabase/migrations/<TS>_feat002_data_model_rls.sql`.
   - Écrit les 3 nouveaux fichiers de tests `supabase/tests/rls_*.sql`.
   - Étend `supabase/tests/rls_landlords.sql` (tests trigger + RPC).
   - Applique la migration sur le schéma `dev` de staging via CLI
     (`supabase db push`) puis lance les tests RLS depuis psql.
3. **security-auditor** :
   - Audit policies (chaque table a SELECT/INSERT/UPDATE explicites,
     pas de policy DELETE, pas de policy permissive `FOR ALL` qui élargirait).
   - Vérifie que les RPC sont `SECURITY DEFINER` avec `SET search_path = public/dev`.
   - Vérifie que `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE TO authenticated`.
   - Vérifie le flag de session `app.allow_deleted_at_change` n'est utilisé
     que dans les RPC.
4. **code-reviewer** : relit la migration (lisibilité, idempotence, parité
   public/dev exacte).
5. **state-keeper** : met à jour `docs/state/SCHEMA.md` après merge.
6. **flutter-dev** : **rien à faire en FEAT-002**. Les modèles freezed
   arriveront en FEAT-003.

Effort estimé total : **M (1-3 jours)** — conforme à la story. Le gros du
travail est l'écriture des tests RLS (~60% du temps) ; la migration SQL elle-même
est mécanique.

---

## 10. Risques

| Risque | Sévérité | Mitigation |
|---|---|---|
| Ordre des triggers BEFORE non garanti par défaut PG | Moyen | Préfixage `tr_01_*`, `tr_02_*` |
| Le flag de session `app.allow_deleted_at_change` est posé hors RPC (régression) | Élevé | Code review obligatoire ; tester qu'un UPDATE direct est bien rejeté |
| Trigger `assert_lease_ownership_consistency` duplique du code public/dev | Faible | Documenter dans le header SQL ; accepter le coût |
| Migration sur le schéma `public` de prod alors qu'aucun trafic prod n'existe encore | Faible | Appliquer d'abord sur `dev`, valider tests, puis sur `public` |
| Performance des sous-requêtes RLS sur les enfants | Faible | Option A élimine la sous-requête (`landlord_id = auth.uid()`) — pas de coût |
| Email regex CHECK trop laxiste (faux positifs/négatifs) | Faible | Validation forte côté Flutter ; le CHECK SQL est un garde-fou minimal |

---

## Récapitulatif des changements vs FEAT-001

| Élément | FEAT-001 | FEAT-002 |
|---|---|---|
| `landlords.id FK auth.users` | ON DELETE CASCADE | ON DELETE NO ACTION ✏️ |
| `landlords` colonnes | id, email, timestamps, deleted_at | + full_name, phone, address ✏️ |
| `properties`, `tenants`, `leases` | — | CRÉÉES ✏️ |
| Trigger `set_updated_at` | landlords uniquement | + 3 nouvelles tables ✏️ |
| Trigger `prevent_protected_columns_change` | — | NOUVEAU sur 4 tables ✏️ |
| Trigger `assert_lease_ownership_consistency` | — | NOUVEAU sur leases ✏️ |
| RPC `soft_delete_*` | — | NOUVELLES (4 fonctions) ✏️ |
| Tests RLS | rls_landlords.sql | + rls_properties.sql + rls_tenants.sql + rls_leases.sql ✏️ |
