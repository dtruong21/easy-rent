# Runbook — Déploiement production Baillan/EasyRent

> Audience : développeur / exploitant.
> Stack : Flutter Web + **Firebase** (Firestore, Auth, Storage, Cloud Functions, Hosting).
> Dernière mise à jour : 2026-07-24.
>
> Backend **100 % Firebase** depuis la migration FEAT-019 : plus aucun backend
> SQL/Postgres externe, ni migration SQL. L'envoi de quittances passe par le
> **partage natif (Web Share API)** côté client — aucun secret email requis.

---

## 1. Pré-requis

### 1.1 Secrets GitHub (environnements `production` et `staging`)

GitHub → Settings → Environments → `production` (puis `staging`) :

| Secret | Valeur | Source |
|---|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | JSON complet du compte de service | Console Firebase → Project Settings → Service Accounts → Generate new private key |
| `FIREBASE_PROJECT_ID` | `easy-rent-54cd4` | Console Firebase |

C'est tout ce dont `deploy.yml` a besoin. La config Firebase Web (apiKey, projectId…)
est embarquée dans `lib/firebase_options.dart` — **publique par design** (sécurité
via Firestore Rules + App Check), donc pas un secret. Seul `--dart-define=APP_ENV`
(dev/prod) est passé au build.

> `production` peut être protégé par « Required reviewers » + wait timer (recommandé).

### 1.2 Firebase Auth — domaines autorisés

Console Firebase → Authentication → Settings → **Authorized domains**. Doivent figurer :

- `baillan.com` (prod) et `app.staging.baillan.com` (app staging)
- `easy-rent-54cd4.web.app` et `baillan-stage.web.app` (domaines Firebase par défaut)
- `localhost` (dev)

Providers actifs : **email/password, Google, Apple, anonyme**. Les emails (vérification,
reset password via `oobCode`) sont envoyés par Firebase Auth ; templates personnalisables
dans Authentication → Templates. **Pas de magic link.**

---

## 2. Ce que déploie la CI vs. ce qui est manuel

| Cible | Comment | Déclencheur |
|---|---|---|
| **Hosting** (app web) | `deploy.yml` → `firebase deploy --only hosting:<target>` | **Auto** : push `main` → prod (`baillan.com`), push `develop` → staging (`app.staging.baillan.com`). **Manuel** : Actions → Deploy → Run workflow (`target` = prod/dev). |
| **Firestore rules + indexes** | `deploy.yml` → cible `firestore:staging` (`develop`) ou `firestore:(default)` (`main`) | **Auto** : même run que le Hosting (cf. [`ENVIRONMENTS.md`](ENVIRONMENTS.md)). Rien à faire à la main, sauf rollback (§5). |
| **Cloud Functions** | **Manuel** : `cd functions && npm ci && npm run build && firebase deploy --only functions` | Avant le deploy app si des functions changent. |
| **Storage rules** | `deploy.yml` → cible `storage` | **Auto, depuis `main` uniquement** (bucket partagé prod/staging : jamais déployé depuis `develop`). Vérifier après le deploy prod qu'un téléversement de document fonctionne (cf. checklist §C). |

> ⚠️ `deploy.yml` déploie le **Hosting**, les **rules + indexes Firestore** et, depuis
> `main`, les **rules Storage**. Les **Cloud Functions** ne sont **pas** automatisées
> (déploiement manuel délibéré) — ne pas les oublier quand une feature en dépend.

> ⚠️ **Prérequis `functions/.env`** (gitignoré, à tenir sur chaque PC qui
> déploie) : il doit déclarer les **12** paramètres de prix Stripe — les 6
> `STRIPE_PRICE_{PRO,MAX,ULTRA}_{MONTHLY,ANNUAL}` et les 6
> `STRIPE_PRICE_{PRO,MAX,ULTRA}_{MONTHLY,ANNUAL}_TEST`. La CLI demande tout
> paramètre absent du fichier, même avec un `default` dans le code : en
> `--non-interactive`, le déploiement échoue sur « In non-interactive mode but
> have no value for the following environment variables ». Tant qu'aucun prix
> live n'existe, les `…_TEST` restent **vides** (repli sur le prix canonique) :
>
> ```
> STRIPE_PRICE_PRO_MONTHLY_TEST=
> STRIPE_PRICE_PRO_ANNUAL_TEST=
> STRIPE_PRICE_MAX_MONTHLY_TEST=
> STRIPE_PRICE_MAX_ANNUAL_TEST=
> STRIPE_PRICE_ULTRA_MONTHLY_TEST=
> STRIPE_PRICE_ULTRA_ANNUAL_TEST=
> ```
>
> Ne jamais committer `functions/.env`.

---

## 3. Procédure de déploiement prod

1. **Staging d'abord** : merger vers `develop` → `deploy.yml` publie l'app staging `app.staging.baillan.com` (et la vitrine staging `stage.baillan.com`).
   Tester (voir [`PROD_DEPLOY_CHECKLIST.md`](PROD_DEPLOY_CHECKLIST.md)).
2. **Backend si besoin** : si la release change des Cloud Functions, les déployer
   manuellement (cf. §2). Rules/indexes (Firestore) et rules Storage partent avec
   `deploy.yml` — validés au préalable en émulateur (`npm run test:rules`) puis staging.
3. **Prod** : merger `develop` → `main` et push. `deploy.yml` (target auto = prod)
   build + publie `baillan.com`, puis **tague la release** (`vX.Y.Z` + GitHub Release
   via `tool/release/release.sh`).
   ```bash
   git checkout main && git pull
   git merge develop        # ou merge de la PR de release
   git push origin main
   ```
4. **Smoke test** prod : [`PROD_DEPLOY_CHECKLIST.md`](PROD_DEPLOY_CHECKLIST.md) §E.

> **Pas de deploy prod sans confirmation utilisateur** (garde-fou `CLAUDE.md`).

---

## 4. Rollback Hosting

```bash
# Lister les versions déployées du site prod
firebase hosting:versions:list --project easy-rent-54cd4

# Restaurer une version précédente sur le canal live du site prod
firebase hosting:clone easy-rent-54cd4:live easy-rent-54cd4:live \
  --version-id=<PREVIOUS_VERSION_ID>
```

Alternative : Actions → Deploy → Run workflow avec `target=prod` sur un tag/commit antérieur.

---

## 5. Rollback backend (rules / functions)

Pas de rollback automatique — redéployer la version antérieure depuis un commit/tag :

- **Rules/indexes** : `git checkout <tag> -- firestore.rules firestore.indexes.json && firebase deploy --only 'firestore:(default)'` pour la prod (`firestore:staging` pour le staging). ⚠️ Jamais `firestore:rules` / `firestore:indexes` sans base : `firebase.json` déclare les deux bases, la commande pousserait aussi sur l'autre.
- **Functions** : rebuild depuis le commit antérieur puis `firebase deploy --only functions`.

**Données** : soft-delete (`deletedAt`) uniquement, jamais de hard-delete. `receipts` est
en rétention légale 5 ans (loi 6/07/1989) — ne jamais supprimer.

---

## 6. Service Worker — stratégie cache

Le build web utilise `--pwa-strategy=none` sur **les deux** environnements : `web/index.html`
porte un script qui désenregistre tout Service Worker (héritage FEAT-019, fix cache-poisoning).

- `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`, `manifest.json` :
  `Cache-Control: no-cache` (revalidation ETag → 304 si inchangé) — voir `firebase.json`.
- Autres assets `.js/.wasm/...` : `no-cache` aussi (Flutter Web ne fingerprint pas les noms).
- Images : `max-age=2592000`.
- SW bloqué chez un utilisateur : `chrome://serviceworker-internals/` → Unregister + hard reload.

> Réactiver l'offline-first = retirer d'abord le script de désenregistrement d'`index.html`,
> puis repasser `--pwa-strategy=offline-first`.

---

## 7. Monitoring (manuel)

Post-deploy, vérifier :

- **Firebase Console** → Hosting (requests), Authentication (erreurs de connexion),
  Firestore (usage / erreurs de règles).
- **Cloud Logging** (`firebase functions:log` ou console GCP) → erreurs Cloud Functions.

Alertes automatisées (Sentry / PagerDuty) : non implémentées — planifiées P1.

---

## 8. Support

- Firebase support : firebase.google.com/support
- Statut : status.firebase.google.com
