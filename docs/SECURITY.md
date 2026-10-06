# EasyRent — Gestion des secrets et sécurité

## 🎯 Modèle de menace

L'app étant une **PWA Flutter Web déployée statiquement sur Firebase Hosting** :
- Tout le code JS/Dart compilé est **téléchargeable et inspectable** par n'importe quel visiteur
- Toute valeur passée via `--dart-define` au moment du build est **embarquée dans le bundle**
- → **Aucune clé "secrète" ne doit toucher le code Flutter**, seulement les clés **publishable**

La vraie sécurité repose sur (**backend 100 % Firebase depuis FEAT-019** — aucun backend SQL/Postgres externe dans le dépôt) :
1. **Règles Firestore** ([`firestore.rules`](../firestore.rules)) : deny-by-default, `isFullyAuthed()` / `isOwner()` — chaque bailleur n'accède qu'à ses données. C'est **la** frontière d'autorisation, il n'y a pas de RLS Postgres.
2. **Cloud Functions** ([`functions/src/`](../functions/src)) : tout traitement nécessitant un secret tourne côté serveur (Stripe, RevenueCat), secrets injectés via Secret Manager (`defineSecret`), jamais via `--dart-define`.
3. **Firebase Auth** : vérifie l'identité ; le contexte d'auth est re-vérifié côté Functions (callables) et côté règles Firestore.

## 🔑 Classification des clés

### ✅ Publiques par design (OK dans le client)

| Clé | Format | Où | Risque si fuite |
|---|---|---|---|
| Firebase config (web) | `apiKey` (`AIza…`), `projectId`, etc. | `firebase_options.dart`, bundle JS | Aucun **tant que les règles Firestore tiennent** — voir ⚠️ ci-dessous |
| Config client | `APP_ENV` | `dart-defines.json`, bundle JS | Aucun |
| Prix Stripe | `STRIPE_PRICE_*` (prix live) et `STRIPE_PRICE_*_TEST` (prix test, staging et émulateur) en `defineString` | Config Functions (`functions/.env`, gitignoré) | Aucun — identifiants de tarif, pas des secrets. La table suit le mode de la clé (`readPriceTable(env)`) ; un `…_TEST` vide retombe sur le prix canonique (transitoire, tant qu'aucune clé live n'existe) |

> ⚠️ **App Check n'est PAS activé** (aucun package `firebase_app_check`, aucune activation dans le code — seul un pod interop transitif apparaît dans `ios/Podfile.lock`). La seule protection derrière la config Firebase publique est donc **les règles Firestore**, sans attestation d'app. Rien d'anormal pour ce stade, mais ne pas documenter App Check comme une protection acquise : il ne l'est pas.

### ❌ Secrètes (NE JAMAIS exposer côté client)

Inventaire vérifié dans [`functions/src/`](../functions/src) (`defineSecret`) et `.github/workflows/` :

| Clé | Format | Où elle DOIT vivre |
|---|---|---|
| `STRIPE_SECRET_KEY` | `sk_live_*` | Secret Manager (`firebase functions:secrets:set`) |
| `STRIPE_SECRET_KEY_TEST` | `sk_test_*` | Secret Manager — servi aux origines staging/émulateur (issue #138) |
| `REVENUECAT_API_KEY` | clé secrète RevenueCat | Secret Manager |
| `REVENUECAT_WEBHOOK_AUTH` | jeton d'auth du webhook entrant | Secret Manager |
| Firebase Admin SDK | `service-account.json` | GitHub Actions secret `FIREBASE_SERVICE_ACCOUNT` (CI uniquement) |
| GitHub PAT | `ghp_*` / `github_pat_*` | macOS Keychain / GitHub Actions |
| Jeton agent Claude Code | — | GitHub Actions secret `CLAUDE_CODE_OAUTH_TOKEN` |

**Note (FEAT-019)** : aucun backend SQL externe dans la stack — pas de client backend tiers, pas de migration SQL. Aucune clé de service serveur type `service_role` à gérer. Le seul secret backend est `FIREBASE_SERVICE_ACCOUNT` (CI, environnements GitHub) ; les clés Firebase Web sont **publiques par design** (sécurité via Firestore Rules + App Check).

**Note (FEAT-008 pivot 2026-06-22)** : `RESEND_API_KEY` a été éliminé. Le partage de quittances utilise Web Share API natif côté client (zéro secret backend email).

**Note (FEAT-011 pivot 2026-06-22)** : Auth magic link (FEAT-001) remplacée par email + password classique. Voir Section "Politique mot de passe" ci-dessous.

**Test simple** : si la clé permet de contourner les règles Firestore, d'agir au nom d'un autre bailleur, ou d'engager de l'argent chez un prestataire (Stripe, RevenueCat), elle est **secrète**. Sinon elle est **publique**.

## 📁 Stockage des clés par environnement

### Développement local
- `dart-defines.json` (gitignoré) → config publique uniquement (`APP_ENV` ; cf. [`dart-defines.example.json`](../dart-defines.example.json))
- `~/.ssh/id_ed25519` → clé SSH GitHub
- Pour les secrets serveur : `firebase functions:secrets:set <NOM>` (stocké dans **Google Secret Manager**, jamais sur disque, jamais dans le bundle)

### CI (GitHub Actions)
`Settings → Secrets and variables → Actions` — liste **réelle**, relevée dans `.github/workflows/` :

| Secret | Usage |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT` | Déploiement Hosting / Functions / rules |
| `FIREBASE_PROJECT_ID` | Cible du déploiement |
| `CLAUDE_CODE_OAUTH_TOKEN` | Workflows d'agents (`ticket-agent`, `ticket-done`) |
| `GITHUB_TOKEN` | Fourni automatiquement par Actions |

> Aucun secret n'est passé à `flutter build` via `--dart-define` : le bundle client ne reçoit que de la config publique. Les secrets serveur ne transitent pas par la CI — ils sont posés directement dans Secret Manager et lus au runtime par les Functions.

### Production (runtime)
- **Frontend** : aucune clé secrète — uniquement la config Firebase publique et `APP_ENV`
- **Cloud Functions** : secrets déclarés par `defineSecret(...)` et résolus depuis Secret Manager à l'exécution (Stripe, RevenueCat)

## 🔄 Rotation des clés

### Quand rotate ?
- 🚨 **Immédiatement** : si une clé est apparue dans git, un screenshot public, un chat externe, un log non-sécurisé
- 🗓 **Périodiquement** : tous les 6 mois pour les secrets (best practice)
- 👤 **Quand un dev quitte** : rotate toutes les clés qu'il a eu accès

### Comment rotate ?

**`STRIPE_SECRET_KEY`** :
1. Dashboard Stripe → Developers → API keys → « Roll key »
2. `firebase functions:secrets:set STRIPE_SECRET_KEY` (colle la nouvelle valeur)
3. Re-déployer les Functions qui la déclarent (`create_checkout_session`, `manage_subscription`, `delete_account`) — un secret n'est relu qu'au déploiement d'une nouvelle révision

⚠️ `STRIPE_SECRET_KEY` doit porter une clé **live** et `STRIPE_SECRET_KEY_TEST` une clé **test** : `resolveStripeKeyOrThrow` (clé choisie par l'Origin) et `resolveStripeKeyForDb` (clé choisie par la base routée : suppression de compte, résiliation mobile) vérifient le préfixe et refusent l'appel en cas d'inversion. Coller une clé live dans le secret de test rouvrirait l'issue #138 — c'est la faute de frappe que cette vérification existe pour attraper.

🔒 `scripts/check-stripe-isolation.sh` (CI) impose que tout fichier de `functions/src/` qui construit un client Stripe ou lit un secret `STRIPE_*` passe par l'un de ces deux résolveurs. Tout nouveau résolveur doit être ajouté à `SANCTIONED_RESOLVERS` dans le script **et** passer par `requireKeyForEnv` (`functions/src/utils/stripe_env.ts`).
4. Stripe laisse une fenêtre de grâce configurable sur l'ancienne clé : surveiller les logs avant de la révoquer définitivement

**`REVENUECAT_API_KEY` / `REVENUECAT_WEBHOOK_AUTH`** :
1. Dashboard RevenueCat → Project Settings → API keys (ou Webhooks → Authorization header)
2. `firebase functions:secrets:set <NOM>`
3. Re-déployer `reconcile_entitlements` (API key) / `revenuecat_webhook` (auth header)
4. ⚠️ Pour le webhook : mettre à jour la valeur **des deux côtés** (RevenueCat + Secret Manager). Décalage = webhooks rejetés, donc entitlements non synchronisés — panne silencieuse côté facturation, à faire en fenêtre courte.

**Firebase Admin SDK / `FIREBASE_SERVICE_ACCOUNT`** :
1. Console GCP → IAM → Comptes de service → clé compromise → Supprimer
2. Créer une nouvelle clé JSON
3. Remplacer le secret GitHub Actions `FIREBASE_SERVICE_ACCOUNT` (JSON complet)
4. Re-lancer un déploiement pour valider


**Clé SSH GitHub** :
1. github.com/settings/keys → Delete la clé
2. `ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_ed25519_new`
3. Ajouter la nouvelle clé à GitHub

## 🛡 Garde-fous techniques activés

- **`.gitignore`** : `dart-defines*.json` (sauf `*.example.json`), `.env*`, `*.pem`, `*.key`, `secrets.json`
- **Pre-commit hook** : [`scripts/check-secrets.sh`](../scripts/check-secrets.sh) bloque tout commit contenant un pattern de secret connu — couvre Stripe `sk_live_`/`rk_live_`, Resend `re_`, GitHub PAT, clés privées PEM, AWS, Google API keys
- **Règles Firestore** : deny-by-default sur toutes les collections, `isFullyAuthed()` / `isOwner()` (enforced par `security-auditor`) — tests dans [`functions/rules-tests/`](../functions/rules-tests)
- **Auth côté Functions** : les callables vérifient le contexte d'auth Firebase avant toute action privilégiée ; le webhook RevenueCat s'authentifie par en-tête partagé (`REVENUECAT_WEBHOOK_AUTH`)

**Angles morts connus du hook** (à traiter si le risque monte) :
- Aucun pattern **RevenueCat** — `REVENUECAT_API_KEY` / `REVENUECAT_WEBHOOK_AUTH` ne seraient pas détectés s'ils étaient collés en clair
- Aucun pattern `sk_test_` (Stripe test) ni `whsec_` (signature webhook Stripe, non utilisée aujourd'hui)
- `docs/SECURITY.md` est **exclu du scan** (il cite les patterns) : ne jamais y coller une vraie valeur, le filet ne rattrapera pas

## 🔎 Audit OWASP du 2026-09-30 — correctifs et points d'attention

Rapport complet : [`docs/security/owasp-audit-2026-09-30.md`](security/owasp-audit-2026-09-30.md) (21 constats ; le **statut des correctifs est en tête du rapport** : 6 constats traités : 01, 02, 05 corrigés ; 04, 06, 09 partiellement (voir le statut de l'audit) sur la branche `fix/owasp-security` — OWASP-21, tests Storage, couvert au passage par OWASP-04 —, les autres reportés).

Garde-fous ajoutés par ces correctifs :

- **Facturation (OWASP-01)** — le webhook RevenueCat route chaque event par `event.environment` : `SANDBOX` → base `staging` uniquement, `PRODUCTION` → `(default)` uniquement, autre/absent → ignoré ; aucun repli sur l'autre base. Exception FEAT-044e : un achat sandbox **App Store / Google Play** d'un uid de `_ops/sandboxAllowlist` (base prod, aucun accès client, édité dans la console) est appliqué à `(default)` — compte de démo App Review, testeurs ; le cron traite aussi cet achat comme un vrai droit. Un achat Stripe test (web staging) n'est jamais concerné, uid listé ou non. Liste illisible : webhook → 500 (RevenueCat retente, rien n'est écrit) ; cron → passage sans liste. `createCheckoutSession` refuse (`landlord_not_found`) un compte sans doc dans la base routée ; hors liste blanche, le cron `reconcileEntitlements` n'accorde ni ne prolonge rien sur un entitlement `is_sandbox` (état enregistré conservé jusqu'à son échéance, #209). Voir [`docs/ENVIRONMENTS.md`](ENVIRONMENTS.md) (« Facturation ») et l'amendement 2026-09-30 de l'[ADR 0003](adr/0003-firestore-prod-staging-isolation.md).
- **Email vérifié (OWASP-02)** — `hasTrustedEmail()` (`email_verified == true` ou provider `google.com` / `apple.com`) est exigée par `isFullyAuthed()` et `isOwner()` dans `firestore.rules` ; seule exception : la création de son propre `landlords/{uid}` à l'inscription (avant la vérification). Côté Functions, `requireVerifiedUid` garde 22 callables ; exemptées : `deleteAccount`, `exportAccountData` (droits RGPD) et `finalizeAnonymousUpgrade` (appelée avant la vérification). Un test de parité impose de classer toute nouvelle callable (gardée ou exemptée).
- **Storage (OWASP-04)** — écriture sous `documents/{uid}/` réservée aux comptes non anonymes à email de confiance (condition dupliquée de `firestore.rules` : toute évolution de l'une doit être reportée dans l'autre), nom d'objet contraint à `{id 20 car.}.(pdf|jpg|png|webp)`, 50 Mio max ; `cleanupExpiredAnon` purge `documents/{uid}/` des anonymes expirés. Tests : `functions/rules-tests/storage_rules.test.ts`. Les objets orphelins (jamais rattachés à un document) ne sont pas purgés (reporté).
- **RGPD (OWASP-05)** — `deleteAccount` hard-delete aussi `charge_statements` et `etat_des_lieux` ; un test de parité impose que toute collection exportée soit purgée ou retenue (seules les `receipts` sont retenues). Les comptes supprimés avant le correctif peuvent avoir laissé ces documents (script ponctuel non écrit).
- **En-têtes HTTP (OWASP-06)** — sur les 4 cibles Hosting : `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, `X-Frame-Options: DENY`. App : `frame-ancestors 'none'` appliqué + CSP complète en **Report-Only** (pas encore bloquante) ; vitrine : CSP appliquée. Détail dans [`docs/state/DEPENDENCIES.md`](state/DEPENDENCIES.md).
- **Dépendances (OWASP-09)** — `npm audit fix` sur `functions/` (lockfile uniquement) : advisories de prod 16 (5 high) → 9 (2 high) ; le reste exige firebase-admin 14 / firebase-functions 7 (montée majeure, reportée).

> ⚠️ **Couplage CSP / `web/index.html`.** La CSP Report-Only de l'app épingle par **sha256** les 2 scripts inline de `web/index.html` (+ 5 scripts injectés par FlutterFire). Modifier le contenu d'un de ces scripts, ou monter FlutterFire, change le hash : à recalculer dans `firebase.json` (blocs `prod` et `stage`) avant de promouvoir la politique en CSP appliquée. Le hash porte sur le texte entre `<script>` et `</script>` — les commentaires HTML autour ne le changent pas. Recalcul : `python3 -c "import re,hashlib,base64;s=open('web/index.html',encoding='utf-8').read();[print('sha256-'+base64.b64encode(hashlib.sha256(m.encode()).digest()).decode()) for m in re.findall(r'<script>(.*?)</script>',s,re.S)]"` (scripts inline sans attribut uniquement ; la console du navigateur indique aussi le hash attendu).

**Déploiement de ces correctifs** (rien n'est déployé par le simple merge de la branche) :
- **Cloud Functions : redéploiement manuel requis** (webhook, checkout, cron de réconciliation, `deleteAccount`, garde des callables, `cleanupExpiredAnon`) — hors CI.
- `firestore.rules` : déployées par la CI (`develop` → `firestore:staging`, `main` → `firestore:(default)`).
- `storage.rules` : déployées par `deploy.yml` depuis `main` uniquement (bucket partagé).
- En-têtes Hosting : déployés avec le Hosting par la CI.
- **Action manuelle recommandée dans RevenueCat** : vérifier les réglages d'environnement du webhook. Un filtre « Production only » ferait doublon avec le routage serveur, mais couperait aussi les events `SANDBOX` qui alimentent la base `staging` (les tests de paiement staging ne la mettraient plus à jour) — à n'activer que si ce besoin disparaît. À confirmer aussi : les valeurs réelles d'`environment` reçues (`SANDBOX` / `PRODUCTION`) sur un event après déploiement.

## ⚠️ Patterns sensibles à connaître

### ~~Flag de session GUC pour bypass contrôlé de trigger (`app.*`)~~ — OBSOLÈTE (FEAT-019)

Cette section décrivait un footgun **Postgres/PostgREST** hérité de FEAT-002 : les RPC `SECURITY DEFINER` `soft_delete_*` posaient un flag `app.allow_deleted_at_change` via `set_config()` pour neutraliser un trigger le temps d'un UPDATE, avec le risque qu'une future RPC passe un paramètre user-contrôlé à `set_config()`.

**Plus rien de tout cela n'existe** : le pivot FEAT-019 a retiré tout backend SQL/Postgres du projet (aucun client backend tiers, aucune migration SQL dans le dépôt). Pas de RPC, pas de trigger SQL, pas de PostgREST — donc pas de surface d'attaque GUC.

Le soft-delete est aujourd'hui porté par les règles Firestore et les Cloud Functions. Les garanties à maintenir sont décrites plus haut (**Garde-fous techniques activés**), pas ici.

> Conservé comme repère pour quiconque retrouverait ces règles dans un doc ou une revue ancienne. Le détail historique reste dans l'historique git et dans `docs/plans/` (archives datées). Le « hardening P1 » associé dans `docs/BACKLOG.md` est sans objet — à fermer si l'entrée y figure encore.

## 🔐 Politique mot de passe (FEAT-011 pivot 2026-06-22 — backend Firebase depuis FEAT-019)

**Authentification** : Email + password classique (remplace magic link FEAT-001). Backend **Firebase Auth** (email/password, Google, Apple, anonyme).

**Hachage** : délégué à **Firebase Auth**, côté serveur (scrypt modifié, implémentation Google — non configurable côté projet). L'app ne voit le mot de passe qu'en mémoire, le temps de l'appel SDK : aucune écriture en localStorage / SharedPreferences (vérifié — aucune persistance de credential dans `lib/`), aucun log.

**Validation** ([`PasswordValidator`](../lib/core/utils/password_validator.dart), **côté client**) :
- Longueur minimale : 8 caractères (`PasswordValidator.minLength`)
- Complexité : au moins 1 lettre (`[a-zA-Z]`) + au moins 1 chiffre (`\d`)
- Pas d'autres restrictions (majuscules, caractères spéciaux optionnels)

> ⚠️ **Cette règle n'est PAS appliquée côté serveur.** Aucune password policy Firebase (Identity Platform) n'est configurée dans le projet : le seul plancher serveur est le rejet natif `weak-password` de Firebase, à **6 caractères**, sans contrainte de composition. Un appel direct à l'API Identity Toolkit, ou un client modifié, peut donc créer un compte à 6 caractères. Acceptable tant que le client officiel est le seul chemin d'écriture ; à durcir (password policy côté Firebase) si le risque devient réel. Cf. `AuthError.weakPassword` ([`auth_error.dart`](../lib/features/auth/domain/auth_error.dart)).

**Transport** : HTTPS exclusif. Tous les formulaires password utilisant TLS 1.3+.

**Rate limiting** : natif Firebase Auth (quotas par IP / par compte, seuils **non publiés** par Google et non configurables — ne pas documenter de chiffre ici, il serait inventé). Se manifeste par le code `too-many-requests`, mappé en `AuthError.tooManyRequests` ([`auth_error_mapper.dart`](../lib/features/auth/data/auth_error_mapper.dart)) et surfacé à l'utilisateur (notamment sur « mot de passe oublié », cf. `forgot_password_controller.dart`). **Aucun throttling custom** côté client ni côté Cloud Functions — vérifié, le seul throttle du codebase concerne le renouvellement d'expiration des sessions anonymes (`anon_expiry_renewer.dart`), sans rapport avec l'auth par mot de passe.

**Session recovery** (Firebase Auth, pivot FEAT-019) : aucun `setPersistence` n'est appelé dans `lib/` — c'est donc la persistance **par défaut** de `firebase_auth_web` qui s'applique, soit la chaîne de repli `indexedDBLocalPersistence` → `browserLocalPersistence` → `browserSessionPersistence` (cf. `getAuthInstance`, `firebase_auth_web/lib/src/interop/auth.dart`). En pratique le jeton vit dans **IndexedDB** ; localStorage n'est qu'un repli si IndexedDB est indisponible (navigation privée, quota). La session survit au refresh **et à la fermeture du navigateur** — elle ne prend fin que sur `signOut()` explicite ([`auth_repository.dart`](../lib/features/auth/data/auth_repository.dart)), suppression de compte, ou révocation du jeton côté Firebase.

**RGPD — « pas de remember me »** : contrainte **révisée le 2026-05-27**, ce n'est plus une dette. La décision figée (`docs/backlog/001-auth-magic-link.md`) retient la persistance standard après fermeture, sans bascule UI « se souvenir de moi », à charge d'en documenter la base légale dans la politique de confidentialité. C'est fait : §7 « Cookies et traceurs » déclare la session Firebase en IndexedDB / cookies first-party ([`privacy_page.dart`](../lib/features/privacy/presentation/privacy_page.dart)). Aucun audit post-MVP n'est en attente sur ce point.

**Reset password** :
- Email de reset avec lien signé (token expiry 1h)
- Redirect `/reset-password?token=<jwt>`
- Validation backend : vérification token JWT + création nouvelle session
- SnackBar confirmation post-reset

**Changement de mot de passe in-app** : ✅ livré (FEAT-025) — l'ancienne mention « impossible, à ajouter en FEAT-012 » était périmée. Flow : `reauthenticateWithPassword` (Firebase exige une session « récente » pour `updatePassword`) puis `updatePassword`, session conservée ([`change_password_controller.dart`](../lib/features/auth/application/change_password_controller.dart)). Échec de ré-auth → `AuthError.currentPasswordIncorrect` ; session trop ancienne → `requires-recent-login`. Le nouveau mot de passe passe par le même `PasswordValidator` que le signup.

## ✅ Checklist avant chaque deploy

- [ ] Aucun secret en clair dans le code (run `scripts/check-secrets.sh --all`)
- [ ] Toute nouvelle collection Firestore a une règle explicite (deny-by-default, `isOwner`/`isFullyAuthed`) — et un test dans `functions/rules-tests/`
- [ ] Toute nouvelle Cloud Function callable vérifie le contexte d'auth avant action privilégiée
- [ ] Tout nouveau secret serveur passe par `defineSecret` + Secret Manager — jamais par `--dart-define`
- [ ] Les secrets CI sont dans GitHub Actions secrets, PAS dans le repo
- [ ] `security-auditor` a donné son OK

## 📞 En cas d'incident (fuite suspectée)

1. **Rotate immédiatement** la clé concernée
2. **Audit des logs** : Firebase Console → Functions → Logs (Cloud Logging) pour les appels serveur ; Firebase Auth → Users pour les connexions anormales ; côté prestataire selon la clé fuitée (Stripe → Developers → Logs / Events, RevenueCat → Webhooks & API logs)
3. **Vérifier les données** : aucune lecture ou écriture massive ? aucune collection touchée par un contournement de règle Firestore ? (Cloud Logging + métriques Firestore)
4. **Documenter** dans `docs/incidents/<date>.md` : quoi, quand, comment, ce qu'on a fait
5. **Notifier la CNIL** si données personnelles compromises (RGPD : 72h)
