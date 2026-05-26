# Schéma Postgres — snapshot

> Maintenu par `state-keeper`. **Source** : `supabase/migrations/`. **Dernière sync** : _(non-initialisé)_

## Tables

_(aucune table créée — le projet n'est pas encore initialisé)_

## Template pour chaque table (à remplir par state-keeper)

```markdown
### `nom_table`
- **Colonnes** : `id uuid PK, landlord_id uuid FK auth.users, ..., created_at, updated_at`
- **Index** : `(landlord_id)`, ...
- **FK** : `landlord_id → auth.users(id) ON DELETE CASCADE`
- **RLS** : ✅ ENABLE
  - `SELECT` : `landlord_id = auth.uid()`
  - `INSERT` : `landlord_id = auth.uid()`
  - `UPDATE` : `landlord_id = auth.uid()`
  - `DELETE` : `landlord_id = auth.uid()`
- **Soft-delete** : oui / non
- **Migrations** : `20260520_init_table.sql`
```

## Storage buckets

_(aucun bucket configuré)_

## Triggers et fonctions Postgres

_(aucune fonction custom)_
