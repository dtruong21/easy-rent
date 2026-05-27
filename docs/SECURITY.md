# EasyRent — Gestion des secrets et sécurité

## 🎯 Modèle de menace

L'app étant une **PWA Flutter Web déployée statiquement sur Firebase Hosting** :
- Tout le code JS/Dart compilé est **téléchargeable et inspectable** par n'importe quel visiteur
- Toute valeur passée via `--dart-define` au moment du build est **embarquée dans le bundle**
- → **Aucune clé "secrète" ne doit toucher le code Flutter**, seulement les clés **publishable**

La vraie sécurité repose sur :
1. **Row Level Security (RLS)** Postgres : chaque user n'accède qu'à ses données
2. **Edge Functions** : tout traitement nécessitant un secret tourne côté serveur
3. **Auth JWT** : Supabase vérifie l'identité avant tout accès aux données

## 🔑 Classification des clés

### ✅ Publiques par design (OK dans le client)

| Clé | Format | Où | Risque si fuite |
|---|---|---|---|
| Supabase Publishable | `sb_publishable_*` | `dart-defines.json`, bundle JS | Aucun direct — RLS protège |
| Supabase URL | `https://*.supabase.co` | `dart-defines.json`, bundle JS | Aucun |
| Firebase config (web) | `apiKey`, `projectId`, etc. | bundle JS | Aucun — App Check/règles protègent |

### ❌ Secrètes (NE JAMAIS exposer côté client)

| Clé | Format | Où elle DOIT vivre |
|---|---|---|
| Supabase Secret | `sb_secret_*` ou `service_role` | Supabase Edge Functions secrets uniquement |
| Resend API Key | `re_*` | Supabase Edge Functions secrets |
| Firebase Admin SDK | service-account.json | GitHub Actions secrets (CI uniquement) |
| GitHub PAT | `ghp_*` | macOS Keychain / GitHub Actions |

**Test simple** : si la clé peut donner un accès admin/bypass-RLS, elle est **secrète**. Sinon elle est **publique**.

## 📁 Stockage des clés par environnement

### Développement local
- `dart-defines.json` (gitignoré) → publishable keys uniquement
- `~/.ssh/id_ed25519` → clé SSH GitHub
- Pour les secrets : `supabase secrets set RESEND_API_KEY=re_...` (stocké côté Supabase, jamais sur disque)

### CI (GitHub Actions)
- `Settings → Secrets and variables → Actions` :
  - `SUPABASE_URL_PROD`
  - `SUPABASE_ANON_KEY_PROD` (publishable)
  - `FIREBASE_SERVICE_ACCOUNT_PROD` (JSON complet du service account)
- Le workflow lit ces secrets et les passe à `flutter build` via `--dart-define`

### Production (runtime)
- Frontend : aucune clé secrète, seulement publishable embarquée au build
- Edge Functions : `supabase secrets set` côté Supabase
- Resend, Stripe, etc. : Edge Functions uniquement

## 🔄 Rotation des clés

### Quand rotate ?
- 🚨 **Immédiatement** : si une clé est apparue dans git, un screenshot public, un chat externe, un log non-sécurisé
- 🗓 **Périodiquement** : tous les 6 mois pour les secrets (best practice)
- 👤 **Quand un dev quitte** : rotate toutes les clés qu'il a eu accès

### Comment rotate ?

**Supabase publishable** (`sb_publishable_*`) :
1. Dashboard Supabase → Project Settings → API
2. Clic "Roll publishable key"
3. Copier la nouvelle clé
4. Remplacer dans `dart-defines.json` + GitHub Actions secrets
5. Re-build et re-deploy

**Supabase secret** (`sb_secret_*`) :
1. Même endroit, "Roll secret key"
2. Mettre à jour Edge Functions secrets : `supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<new>`
3. Re-deploy les Edge Functions concernées
4. Surveiller les logs : ancien key continue de fonctionner 1h en grace period

**Resend** :
1. resend.com → API Keys → Revoke la clé fuitée
2. Créer une nouvelle clé
3. `supabase secrets set RESEND_API_KEY=<new>`

**Clé SSH GitHub** :
1. github.com/settings/keys → Delete la clé
2. `ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_ed25519_new`
3. Ajouter la nouvelle clé à GitHub

## 🛡 Garde-fous techniques activés

- **`.gitignore`** : `dart-defines.json`, `.env*`, `*.pem`, `*.key`, `secrets.json`, `supabase/.env`
- **Pre-commit hook** : `scripts/check-secrets.sh` bloque tout commit contenant un pattern de secret connu
- **RLS** : activée sur toutes les tables (enforced par `supabase-dev` et `security-auditor`)
- **JWT verification** : toutes les Edge Functions vérifient le JWT avant action privilégiée

## ✅ Checklist avant chaque deploy

- [ ] Aucun secret en clair dans le code (run `scripts/check-secrets.sh`)
- [ ] Toutes les tables nouvelles ont RLS activée
- [ ] Toutes les Edge Functions valident le JWT
- [ ] Les secrets de prod sont dans GitHub Actions secrets, PAS dans le repo
- [ ] `security-auditor` a donné son OK

## 📞 En cas d'incident (fuite suspectée)

1. **Rotate immédiatement** la clé concernée
2. **Audit Supabase logs** : Dashboard → Logs → filtrer par IP suspecte ou requêtes anormales
3. **Vérifier les données** : aucune extraction massive ? aucune table touchée par RLS bypass ?
4. **Documenter** dans `docs/incidents/<date>.md` : quoi, quand, comment, ce qu'on a fait
5. **Notifier la CNIL** si données personnelles compromises (RGPD : 72h)
