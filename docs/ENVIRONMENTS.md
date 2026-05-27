# EasyRent — Stratégie multi-environnement (free tier Supabase)

> Un seul projet Supabase, deux environnements (`dev` et `prod`) isolés au niveau du schéma Postgres et des chemins Storage.

## 🎯 Contrainte de base

Le free tier Supabase impose un seul projet utilisable. Donc :
- ✅ Un seul instance Postgres
- ✅ Une seule table `auth.users` (partagée)
- ✅ Un seul Storage
- ✅ Un seul jeu d'Edge Functions
- ✅ Un seul jeu de secrets

→ Il faut **séparer les données au niveau applicatif** sans pouvoir s'appuyer sur l'isolation native.

## 🗄 Stratégie Postgres : schémas séparés

### Architecture

| Schéma | Rôle | Branche Git mappée |
|---|---|---|
| `public` | **PROD** | `main` → Firebase live |
| `dev` | **DEV / staging** | `develop` → Firebase staging |

Les deux schémas contiennent les **mêmes tables avec la même structure**, mais des données isolées. Chaque user vit dans les deux schémas indépendamment (RLS par `auth.uid()`).

### Convention de migration

Chaque migration applique les changements **aux deux schémas en une seule fois**. Pattern recommandé :

```sql
-- Migration: 20260601_create_landlords.sql

-- ============ PROD (public) ============
CREATE TABLE public.landlords (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  display_name text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.landlords ENABLE ROW LEVEL SECURITY;
CREATE POLICY "landlord_owns_self" ON public.landlords
  FOR ALL USING (id = auth.uid()) WITH CHECK (id = auth.uid());
CREATE INDEX idx_public_landlords_email ON public.landlords(email);

-- ============ DEV (dev) ============
CREATE TABLE dev.landlords (LIKE public.landlords INCLUDING ALL);
ALTER TABLE dev.landlords ENABLE ROW LEVEL SECURITY;
CREATE POLICY "landlord_owns_self" ON dev.landlords
  FOR ALL USING (id = auth.uid()) WITH CHECK (id = auth.uid());
-- Note: INCLUDING ALL copie les indexes, mais PAS les policies → on les recrée
```

**Règle d'or** : chaque migration touchant des tables doit éditer les deux schémas. L'agent `supabase-dev` et `security-auditor` vérifient ça.

### Switch côté Flutter

L'app choisit son schéma via `--dart-define=SUPABASE_SCHEMA=dev|public` :

```dart
// lib/core/config/env.dart
static const String supabaseSchema = String.fromEnvironment(
  'SUPABASE_SCHEMA',
  defaultValue: 'public',  // safer default = prod-like
);
```

Et toutes les requêtes passent par un wrapper :

```dart
// lib/core/db.dart
class Db {
  static SupabaseQueryBuilder from(String table) {
    return Supabase.instance.client.schema(Env.supabaseSchema).from(table);
  }
}

// Usage : Db.from('landlords').select() au lieu de Supabase.instance.client.from(...)
```

## 📁 Storage : préfixage par environnement

Un seul bucket `documents`, paths préfixés :

```
documents/
├── prod/
│   ├── {user_id}/
│   │   ├── leases/
│   │   ├── receipts/
│   │   └── identity/
├── dev/
│   ├── {user_id}/
│   │   └── ...
```

Convention d'upload côté Flutter :
```dart
final path = '${Env.storageEnvPrefix}/$userId/leases/$fileName';
// storageEnvPrefix = 'prod' si schema=public, 'dev' sinon
```

### Politique du bucket (à configurer dans Supabase Studio)

```sql
-- Un user ne peut accéder qu'à ses propres fichiers dans son env
CREATE POLICY "user_accesses_own_env_files"
ON storage.objects FOR ALL
USING (
  bucket_id = 'documents'
  AND auth.uid()::text = (storage.foldername(name))[2]  -- {env}/{user_id}/...
);
```

## 👥 Auth : convention email

Comme `auth.users` est partagée, on ne peut pas isoler techniquement les comptes dev des comptes prod.

**Convention** :
- **Comptes dev** : email avec `test+` (Gmail+ alias) → `test+demo1@gmail.com`, `test+dev2@gmail.com`
- **Comptes prod** : tout le reste

→ Ce n'est pas une garde technique stricte, mais une discipline d'équipe. Nettoyage périodique recommandé.

### Helper SQL (optionnel, pour les audits)

```sql
-- Liste les comptes "test" qui se sont créés en prod
SELECT id, email, created_at
FROM auth.users
WHERE email ILIKE 'test+%';
```

### Garde-fou applicatif (recommandé après MVP)

Quand tu auras le temps, ajoute un trigger Postgres qui empêche les emails `test+` de créer des données dans le schéma `public` :

```sql
CREATE OR REPLACE FUNCTION block_test_emails_in_prod()
RETURNS trigger AS $$
DECLARE
  user_email text;
BEGIN
  SELECT email INTO user_email FROM auth.users WHERE id = auth.uid();
  IF user_email ILIKE 'test+%' THEN
    RAISE EXCEPTION 'Test accounts cannot create data in prod schema';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- À appliquer sur chaque table public :
CREATE TRIGGER block_test_emails_landlords
  BEFORE INSERT OR UPDATE ON public.landlords
  FOR EACH ROW EXECUTE FUNCTION block_test_emails_in_prod();
```

## ⚙️ Edge Functions

Une seule version déployée, qui gère les deux schémas via un paramètre :

```typescript
// supabase/functions/send-receipt/index.ts
const { receiptId, schema = 'public' } = await req.json();

if (!['public', 'dev'].includes(schema)) {
  return new Response('Invalid schema', { status: 400 });
}

const { data } = await supabaseAdmin
  .schema(schema)
  .from('receipts')
  .select('*')
  .eq('id', receiptId)
  .single();
```

Le client Flutter passe le schéma en argument :
```dart
await Supabase.instance.client.functions.invoke('send-receipt', body: {
  'receiptId': id,
  'schema': Env.supabaseSchema,
});
```

## 🔐 Secrets et clés

Les secrets Supabase (Resend API, etc.) sont **partagés** entre dev et prod (un seul projet). Conséquences :
- ✅ Simplicité de config
- ⚠️ Une fuite de clé en dev affecte aussi la prod
- ⚠️ Resend envoie de vrais emails depuis dev → utiliser un domaine de test Resend (sandbox)

**Recommandation** : configurer Resend en sandbox mode pour dev, prod mode pour production. À gérer applicativement :

```typescript
const resendDomain = schema === 'dev' ? 'sandbox.tondomaine.fr' : 'quittances.tondomaine.fr';
```

## 🚀 Déploiement

| Push sur | Action |
|---|---|
| `develop` | Build avec `SUPABASE_SCHEMA=dev` → Firebase staging |
| `main` | Build avec `SUPABASE_SCHEMA=public` → Firebase live (confirmation requise) |
| `feature/*` (PR open) | Preview deploy temporaire sur Firebase staging avec schéma `dev` |

## 🧹 Maintenance périodique

À faire ~1x/mois :
- [ ] Nettoyer les comptes `test+*` qui se seraient créés en prod
- [ ] Vacuum les tables `dev` (peuvent grossir avec les essais)
- [ ] Vérifier que les schémas sont synchronisés (mêmes tables/colonnes/policies)
- [ ] Auditer Storage : volume `dev/` vs `prod/`

Script utile :
```sql
-- Vérifier la parité des schémas
SELECT
  pub.tablename AS public_table,
  dev.tablename AS dev_table
FROM pg_tables pub
FULL OUTER JOIN pg_tables dev
  ON pub.tablename = dev.tablename AND dev.schemaname = 'dev'
WHERE pub.schemaname = 'public' OR dev.schemaname = 'dev';
-- Toute ligne avec une cellule NULL = drift à corriger
```

## ⏭️ Évolution future (quand tu upgradeads Supabase Pro)

À l'upgrade vers Pro :
1. Crée un second projet Supabase
2. Déplace le schéma `dev` vers le nouveau projet
3. Supprime le schéma `dev` du projet originel (qui devient pur prod)
4. Update `dart-defines.dev.json` avec la nouvelle URL/key du projet dev
5. Update `dart-defines.prod.json` reste inchangé

La logique applicative (`Db.from()`, env switching) ne change pas.
