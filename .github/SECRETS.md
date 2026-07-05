# GitHub Actions — Secrets requis

> Configurés dans **Settings → Environments** (un environnement par cible : `staging`, `production`).

## Secrets par environnement (deploy)

| Nom | Valeur | Où la trouver |
|---|---|---|
| `SUPABASE_URL` | `https://<ref>.supabase.co` | Supabase Dashboard → Project Settings → API |
| `SUPABASE_ANON_KEY` | `sb_publishable_*` | Idem (publishable key) |
| `SUPABASE_PROJECT_REF` | `<ref>` (alphanumérique) | Supabase Dashboard URL ou Settings → General |
| `SUPABASE_ACCESS_TOKEN` | `sbp_*` | https://supabase.com/dashboard/account/tokens (personal token) |
| `SUPABASE_DB_PASSWORD` | mot de passe DB | Supabase Dashboard → Database → Settings |
| `FIREBASE_PROJECT_ID` | `<project-id>` | Firebase Console → Project Settings |
| `FIREBASE_SERVICE_ACCOUNT` | JSON complet | Firebase Console → Project Settings → Service Accounts → Generate new private key |

## Secrets globaux (repo-level, pas par environment)

Configure dans **Settings → Secrets and variables → Actions → New repository secret** :

| Nom | Valeur | Utilisé par |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Long token alphanumérique | `ticket-agent.yml` — Claude Code via abonnement (Team/Pro/Max) |

### 🔑 Générer le `CLAUDE_CODE_OAUTH_TOKEN`

Cet OAuth token authentifie ton GitHub Action contre ton **abonnement Claude** (pas l'API → pas de facturation au token, juste la cap mensuelle de ton plan).

1. Ouvre un terminal sur ton Mac (avec Claude Code installé localement)
2. Lance :
   ```bash
   claude setup-token
   ```
3. Suis l'authentification dans le navigateur (login Claude)
4. Le token s'affiche dans le terminal — copie-le
5. GitHub repo → Settings → Secrets and variables → Actions → New repository secret
6. Name : `CLAUDE_CODE_OAUTH_TOKEN`
7. Value : le token copié
8. Add secret

### ⚠️ Notes importantes

- **Team Plan** : l'usage consommé via CI s'ajoute à ton compteur d'équipe. Vérifie avec ton admin que c'est OK avant de lancer la première run.
- **Passage Pro plus tard** : régénère un nouveau token après avoir switché ton compte (`claude setup-token` à nouveau), puis update le secret GitHub.
- **Rotation** : régénère un token tous les 6 mois ou si tu suspectes une fuite. L'ancien token reste valide jusqu'à sa révocation.
- **Visibility** : Le token donne accès à TES requêtes Claude (consomme TA cap). Si compromis, révoque-le sur claude.ai → Settings → Account → API tokens.

### Alternative : API pay-as-you-go (si tu veux contourner l'abonnement)

Remplace dans `ticket-agent.yml` :
```yaml
# claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```
Et ajoute le secret `ANTHROPIC_API_KEY` (depuis https://console.anthropic.com/settings/keys). Mais c'est plus cher.

## Secrets côté Supabase (Edge Functions)

À configurer via `supabase secrets set` — **JAMAIS dans GitHub Actions secrets** :

```bash
supabase secrets set RESEND_API_KEY=re_xxxxx
supabase secrets set FROM_EMAIL=quittances@tondomaine.fr
```

## Comment configurer les environnements GitHub

1. Repo → Settings → Environments → New environment
2. Crée `staging` et `production`
3. Pour chacun, ajoute les secrets ci-dessus avec leurs valeurs spécifiques
4. **Optionnel mais recommandé** pour `production` :
   - Required reviewers (toi-même comme approver)
   - Wait timer (5 min de cooldown)
   - Restrict deployments à `main` only

## Procédure si une clé fuit dans CI logs

1. Désactive immédiatement le workflow concerné
2. Rotate la clé fuitée (voir `docs/SECURITY.md`)
3. Mets à jour le secret dans GitHub
4. Re-lance le workflow
5. Note l'incident dans `docs/incidents/`
