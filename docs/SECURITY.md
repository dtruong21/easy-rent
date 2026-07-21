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
| Firebase Admin SDK | service-account.json | GitHub Actions secrets (CI uniquement) |
| GitHub PAT | `ghp_*` | macOS Keychain / GitHub Actions |

**Note (FEAT-008 pivot 2026-06-22)** : `RESEND_API_KEY` a été éliminé. Le partage de quittances utilise Web Share API natif côté client (zéro secret backend email).

**Note (FEAT-011 pivot 2026-06-22)** : Auth magic link (FEAT-001) remplacée par email + password classique. Voir Section "Politique mot de passe" ci-dessous.

**Test simple** : si la clé peut donner un accès admin/bypass-RLS, elle est **secrète**. Sinon elle est **publique**.

## 📁 Stockage des clés par environnement

### Développement local
- `dart-defines.json` (gitignoré) → publishable keys uniquement
- `~/.ssh/id_ed25519` → clé SSH GitHub
- Pour les secrets : `supabase secrets set <VAR>=<VAL>` (stocké côté Supabase, jamais sur disque)

### CI (GitHub Actions)
- `Settings → Secrets and variables → Actions` :
  - `SUPABASE_URL_PROD`
  - `SUPABASE_ANON_KEY_PROD` (publishable)
  - `FIREBASE_SERVICE_ACCOUNT_PROD` (JSON complet du service account)
- Le workflow lit ces secrets et les passe à `flutter build` via `--dart-define`

### Production (runtime)
- Frontend : aucune clé secrète, seulement publishable embarquée au build
- Edge Functions : `supabase secrets set` côté Supabase (pour services externes si utilisés)

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


**Clé SSH GitHub** :
1. github.com/settings/keys → Delete la clé
2. `ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_ed25519_new`
3. Ajouter la nouvelle clé à GitHub

## 🛡 Garde-fous techniques activés

- **`.gitignore`** : `dart-defines.json`, `.env*`, `*.pem`, `*.key`, `secrets.json`, `supabase/.env`
- **Pre-commit hook** : `scripts/check-secrets.sh` bloque tout commit contenant un pattern de secret connu
- **RLS** : activée sur toutes les tables (enforced par `supabase-dev` et `security-auditor`)
- **JWT verification** : toutes les Edge Functions vérifient le JWT avant action privilégiée

## ⚠️ Patterns sensibles à connaître

### Flag de session GUC pour bypass contrôlé de trigger (`app.*`)

Depuis FEAT-002, un flag de session custom `app.allow_deleted_at_change` est utilisé par les RPC `SECURITY DEFINER` `soft_delete_*` pour neutraliser temporairement le trigger `prevent_protected_columns_change` le temps d'un UPDATE légitime sur `deleted_at`.

**Comment ça marche** :
- Chaque RPC pose `set_config('app.allow_deleted_at_change', '1', true)` (true = scope local-transaction)
- Le trigger lit ce flag via `current_setting('app.allow_deleted_at_change', true)` et autorise l'UPDATE si présent

**Risque architectural** : Postgres autorise n'importe quel rôle (y compris `authenticated`) à poser un paramètre GUC custom (préfixe `app.*`) via `SET LOCAL` ou `set_config()`. Aujourd'hui ce risque est mitigé parce que PostgREST n'expose ni `pg_catalog.set_config` ni de fonction `public.*` qui ferait du passthrough. **Mais c'est un footgun** : si demain quelqu'un ajoute une RPC qui prend un paramètre user-controlled et le passe à `set_config()`, le bypass devient possible.

**Règles à respecter strictement** :
1. ❌ **JAMAIS** créer une fonction `public.*` (ou exposée à PostgREST) qui accepte un nom de variable ou une valeur GUC en paramètre user-contrôlé.
2. ❌ **JAMAIS** appeler `set_config(p_var, p_val, ...)` où `p_var` ou `p_val` vient d'un argument de fonction publique.
3. ✅ Si une RPC doit positionner un flag de session, **les deux arguments doivent être des littéraux hardcodés** dans le corps de la fonction (`set_config('app.x', '1', true)`).
4. ✅ Les RPC qui posent des flags doivent être `SECURITY DEFINER` + `SET search_path = public` (ou `= dev`) + `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE TO authenticated`.
5. ✅ Toute nouvelle RPC qui touche `set_config()` requiert une revue explicite par `security-auditor` avant merge.

**Hardening prévu en P1** : remplacer le flag par un mécanisme intransférable (ex: `pg_trigger_depth() > 0` testé dans une fonction SECURITY DEFINER de niveau supérieur), afin de retirer toute surface d'attaque future. Tracké dans `docs/BACKLOG.md` (dette technique post-FEAT-002).

## 🔐 Politique mot de passe (FEAT-011 pivot 2026-06-22)

**Authentification** : Email + password classique (remplace magic link FEAT-001).

**Hachage** : Bcrypt côté Supabase. Jamais en clair côté client, jamais stocké en localStorage.

**Validation** (Supabase built-in `letters_digits`) :
- Longueur minimale : 8 caractères
- Complexité : au moins 1 lettre + 1 chiffre
- Pas d'autres restrictions (majuscules, caractères spéciaux optionnels)

**Transport** : HTTPS exclusif. Tous les formulaires password utilisant TLS 1.3+.

**Rate limiting** : Supabase built-in 3 tentatives/minute. Pas de throttling custom côté client.

**Session recovery** (Firebase Auth, pivot FEAT-019) : aucun `setPersistence` n'est appelé dans `lib/` — c'est donc la persistance **par défaut** de `firebase_auth_web` qui s'applique, soit la chaîne de repli `indexedDBLocalPersistence` → `browserLocalPersistence` → `browserSessionPersistence` (cf. `getAuthInstance`, `firebase_auth_web/lib/src/interop/auth.dart`). En pratique le jeton vit dans **IndexedDB** ; localStorage n'est qu'un repli si IndexedDB est indisponible (navigation privée, quota). La session survit au refresh **et à la fermeture du navigateur** — elle ne prend fin que sur `signOut()` explicite ([`auth_repository.dart`](../lib/features/auth/data/auth_repository.dart)), suppression de compte, ou révocation du jeton côté Firebase.

**RGPD — « pas de remember me »** : contrainte **révisée le 2026-05-27**, ce n'est plus une dette. La décision figée (`docs/backlog/001-auth-magic-link.md`) retient la persistance standard après fermeture, sans bascule UI « se souvenir de moi », à charge d'en documenter la base légale dans la politique de confidentialité. C'est fait : §7 « Cookies et traceurs » déclare la session Firebase en IndexedDB / cookies first-party ([`privacy_page.dart`](../lib/features/privacy/presentation/privacy_page.dart)). Aucun audit post-MVP n'est en attente sur ce point.

**Reset password** :
- Email de reset avec lien signé (token expiry 1h)
- Redirect `/reset-password?token=<jwt>`
- Validation backend : vérification token JWT + création nouvelle session
- SnackBar confirmation post-reset

**No password change** (MVP) : Utilisateur connecté ne peut pas changer password. À ajouter FEAT-012. Workaround : "Mot de passe oublié?" → reset via email.

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
