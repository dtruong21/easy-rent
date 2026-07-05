# Runbook — 1er déploiement production EasyRent

> Audience : développeur / exploitant EasyRent.
> Durée estimée (1er deploy) : 2–3 heures.
> Dernière mise à jour : 2026-06-22
> 
> **FEAT-008 pivot (2026-06-22)** : L'envoi de quittances utilise le partage natif Web Share API côté client. Aucun secret backend email requis.

---

## 1. Pré-requis

Avant de lancer le déploiement, les éléments suivants doivent être disponibles :

### 1.1 Secrets GitHub (environnement `production`)

Aller dans GitHub → Settings → Environments → `production` → Add secret pour chacun :

| Secret | Valeur | Source |
|---|---|---|
| `SUPABASE_URL` | `https://tbgttutodbqffrvsvkoz.supabase.co` | Dashboard Supabase → Settings → API |
| `SUPABASE_ANON_KEY` | clé anon (commence par `eyJ...`) | Dashboard Supabase → Settings → API |
| `FIREBASE_SERVICE_ACCOUNT` | JSON du compte de service | Console Firebase → Project Settings → Service Accounts → Generate |
| `FIREBASE_PROJECT_ID` | `easy-rent-54cd4` | Console Firebase |
| `SUPABASE_PROJECT_REF` | `tbgttutodbqffrvsvkoz` | Dashboard Supabase (ID projet) |
| `SUPABASE_ACCESS_TOKEN` | `sbp_xxx...` | Dashboard Supabase → Account → Access Tokens |
| `SUPABASE_DB_PASSWORD` | mot de passe DB | Dashboard Supabase → Settings → Database |

### 1.2 Supabase Auth — Configuration URL

Dans Dashboard Supabase → Authentication → URL Configuration :

- **Site URL** : `https://easy-rent-54cd4.web.app`
- **Redirect Allow-List** : `https://easy-rent-54cd4.web.app/**`

Sans cette configuration, les magic links redirigeront vers une mauvaise URL et l'authentification échouera en production.

**Remarque** : Aucun secret email n'est requis. Le partage de quittances utilise le Web Share API natif côté client.

---

## 2. Procédure 1er déploiement (séquence)

### Étape a. Configurer Supabase Auth URL

Voir §1.3 ci-dessus.

### Étape b. Déployer les Edge Functions sur prod

```bash
# Authentification Supabase CLI
supabase login

# Lier le projet
supabase link --project-ref tbgttutodbqffrvsvkoz

# Déployer les functions
supabase functions deploy generate-receipt --project-ref tbgttutodbqffrvsvkoz
```

### Étape c. Appliquer les migrations (workflow_dispatch)

Sur GitHub → Actions → "Apply migrations to PROD (manuel)" :
1. Cliquer "Run workflow"
2. Saisir `dry_run: true` → vérifier la liste des migrations
3. Re-lancer avec `dry_run: false` et `confirmation: yes`
4. Vérifier la réussite dans les logs

### Étape d. Déployer l'app (push sur main)

```bash
git checkout main
git merge develop   # ou merge PR feature/dashboard-pwa-prod-setup
git push origin main
```

Le workflow `deploy.yml` se déclenche automatiquement → Build + Firebase Hosting.

### Étape e. Smoke test

Suivre la checklist `docs/PROD_DEPLOY_CHECKLIST.md` (15 étapes).

---

## 3. Re-déploiements réguliers

Pour chaque nouvelle version :

1. Merger la feature branch vers `develop` → staging auto-déployé.
2. Tester en staging.
3. Merger `develop` → `main` → prod auto-déployé.
4. Si nouvelle migration : lancer `migrate-prod.yml` workflow_dispatch **avant** le merge main.

---

## 4. Rollback Hosting

### Option 1 — Rapide (interface Firebase)

```bash
# Lister les versions déployées
firebase hosting:versions:list --project easy-rent-54cd4

# Cloner une version précédente vers le canal live
firebase hosting:clone easy-rent-54cd4:live easy-rent-54cd4:live \
  --version-id=<PREVIOUS_VERSION_ID>
```

### Option 2 — Redéploiement d'un commit antérieur

Sur GitHub → Actions → "Deploy" → Run workflow (override = prod, branche = tag/commit cible).

---

## 5. Rollback migrations

**Aucun rollback automatique.**

En cas de migration qui casse prod :

1. Identifier la migration problématique.
2. Créer une migration de correction dans `supabase/migrations/` (ex: `YYYYMMDD_fix_xxx.sql`).
3. Tester en staging (`develop` → staging → `migrate-prod.yml` dry-run).
4. Lancer `migrate-prod.yml` sur prod avec `confirmation=yes`.

**Interdit** : `DROP TABLE`, `TRUNCATE`, suppression de colonnes sur tables avec `legal_hold`.

---

## 6. Service Worker — Cache stale

Le build prod utilise `--pwa-strategy=offline-first` (Flutter par défaut).

- `flutter_service_worker.js` est servi avec `Cache-Control: no-cache, no-store, must-revalidate`
  via une règle explicite dans `firebase.json` (règle placée AVANT la règle `*.js` immutable,
  Firebase prenant la première règle qui correspond).
- `index.html` est également servi avec `no-cache, no-store, must-revalidate`.
- Les autres assets `.js` (dont `main.dart.js`) conservent `max-age=31536000, immutable`
  (hash de contenu dans le nom de fichier → safe).
- `manifest.json` n'a pas de règle explicite → cache court par défaut Firebase (acceptable MVP).
- Le SW Flutter invalide automatiquement le cache quand le hash de `main.dart.js` change.
- En cas de SW bloqué chez un utilisateur : `chrome://serviceworker-internals/` → "Unregister" + hard reload.

---

## 7. Monitoring (MVP — manuel)

Pendant les 48h post-deploy, vérifier 2x/jour :

- **Supabase Dashboard** → Logs (Auth errors, Edge Function failures)
- **Firebase Hosting** → Usage / Requests (console.firebase.google.com)

Alertes automatisées (Sentry, Pagerduty) : non implémentées en MVP — planifiées P1.

---

## 8. Contacts en cas de problème

- Supabase support : supabase.com/support
- Firebase support : firebase.google.com/support
- Resend support : resend.com/docs
