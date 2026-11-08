# Checklist — Déploiement production Baillan/EasyRent

> Cocher chaque item avant / pendant / après le déploiement.
> Durée estimée : ~30 min (smoke test) + provisionnement initial la 1ère fois.
> Dernière mise à jour : 2026-10-05 (release v1.1.0). Backend **100 % Firebase** (Firestore, Auth, Storage, Cloud Functions, Hosting).

---

## A. Secrets GitHub (environnement `production`)

GitHub → Settings → Environments → `production` :

- [ ] `FIREBASE_SERVICE_ACCOUNT` provisionné (JSON complet du compte de service)
- [ ] `FIREBASE_PROJECT_ID` provisionné (`easy-rent-54cd4`)
- [ ] Environnement `production` configuré avec « Required reviewers » (recommandé)

> Aucun secret email : les quittances sont partagées via la Web Share API côté client.
> La config Firebase Web vit dans `lib/firebase_options.dart` (publique), pas en secret.

---

## B. Firebase Auth (Console Firebase → Authentication)

- [ ] **Authorized domains** contiennent `baillan.com`, `app.staging.baillan.com`,
  `easy-rent-54cd4.web.app`, `baillan-stage.web.app`, `localhost`
- [ ] Providers activés : **Email/Password**, **Google**, **Anonymous** (Apple peut rester activé : la v1 ne l'affiche pas — #214, email seul sur iOS)
- [ ] (Optionnel) Templates d'email (vérification / reset password) personnalisés dans
  Authentication → Templates

> Politique mot de passe (8 caractères, lettres + chiffres) appliquée côté client
> (validators Dart). Reset password via `oobCode` lu dans l'URL — pas de session recovery.

---

## C. Backend Firebase (si la release le modifie)

> `deploy.yml` déploie le Hosting, les rules + indexes Firestore et (depuis `main`) les rules Storage.
> Seules les **Cloud Functions** sont **manuelles**.

- [ ] Rules testées en émulateur : `cd functions && npm run test:rules` (cross-user OK)
- [ ] Rules + indexes Firestore : **auto** par `deploy.yml` (`firestore:staging` sur `develop`, `firestore:(default)` sur `main`) — vérifier l'étape dans le run
- [ ] `functions/.env` déclare les 12 `STRIPE_PRICE_*` et `STRIPE_PRICE_*_TEST` (les `…_TEST` peuvent être vides), sinon `--non-interactive` échoue — cf. [`RUNBOOK_PROD_DEPLOY.md`](RUNBOOK_PROD_DEPLOY.md) §2
- [ ] `cd functions && npm ci && npm run build && firebase deploy --only functions` (si functions changées)
- [ ] Rules Storage : **auto** par `deploy.yml` depuis `main` uniquement (cible `storage`, bucket partagé) — vérifier l'étape dans le run, puis **téléverser un document sur prod ET sur staging juste après le déploiement** (compte non anonyme à email vérifié ; un échec = règles Storage ou email non vérifié)
- [ ] **1er run des cibles `firestore:(default)` et `storage` depuis `main`** (ajoutées après la v1.0.0) : le compte de service CI a `firebaserules.admin`, `datastore.indexAdmin`, `firebasehosting.admin`. En cas de `403` sur une étape, ajouter le rôle nommé dans l'erreur (action Daki, IAM) puis « Re-run failed jobs » — un re-run redéploie à l'identique, sans second tag
- [ ] Index composites Firestore prod : attendre « Enabled » (console → Firestore → Indexes) avant le smoke test — les écrans qui en dépendent échouent tant qu'ils se construisent
- [ ] ⚠️ **Comptes prod sans email vérifié (v1.1.0)** : les nouvelles règles Firestore et Storage exigent `hasTrustedEmail()` (email vérifié **ou** connexion Google/Apple) ; un compte email/mot de passe non vérifié perd l'accès au déploiement (les comptes anonymes ne sont pas concernés). **Avant le merge**, lister ces comptes — console Firebase → Authentication (colonne « Vérifié »), ou `firebase auth:export users.json --project easy-rent-54cd4 --format=json` puis filtrer les utilisateurs dont `providerUserInfo` contient `password` et `emailVerified` n'est pas vrai (vérifier la forme du JSON à l'usage). Pour chacun : le faire vérifier (lien de vérification) ou accepter consciemment le blocage. L'export contient des données personnelles et des hash : **ne pas le commiter, le supprimer après usage**.
- [ ] **Cloud Functions déployées = `develop`** : prod et staging partagent les mêmes Functions (déploiement manuel). Vérifier que le dernier déploiement est postérieur au dernier commit touchant `functions/src` (`git log -1 --format=%cI -- functions/src`) ; sinon redéployer (`firebase deploy --only functions`). `firebase functions:list` doit montrer les fonctions attendues (38 au 2026-10-04, cf. `docs/state/functions/README.md`). Le bouton « Passer à la facturation annuelle/mensuelle » de `/pro` exige l'action `current_plan` de `manageSubscription` (2026-10-09) : sans ce redéploiement il reste simplement masqué.

---

## D. Build + Deploy

- [ ] Merge feature branch → `develop` → staging déployé (`app.staging.baillan.com`)
- [ ] Tests manuels en staging passent
- [ ] Merge `develop` → `main` → workflow `deploy.yml` prod déclenché
- [ ] Build GitHub Actions : pas d'erreur dans les logs
- [ ] Firebase Hosting : déploiement du site prod (canal `live`) réussi
- [ ] Tag `vX.Y.Z` + GitHub Release créés (step « Tag release » du workflow)

---

## E. Smoke test (~30 min)

Ouvrir **https://baillan.com** dans Chrome (fallback : `easy-rent-54cd4.web.app`).

- [ ] La page de login s'affiche correctement (pas de page blanche)
- [ ] Cliquer « Politique de confidentialité » → page `/privacy` complète s'affiche sans login
- [ ] **Signup** : créer un compte (email réel + password 8 chars + lettre + chiffre + RGPD coché) → redirect dashboard, session active
- [ ] **Login** : logout + re-login email + password → connexion OK
- [ ] **Google** : connexion Google (web) → OK. Apple n'est pas proposé en v1
- [ ] **Mauvais password** : password incorrect → message « Email ou mot de passe incorrect » + email conservé
- [ ] **Reset password** : `/forgot-password` → email reçu → lien → `/reset-password` → nouveau password → redirect `/login` + snackbar → login avec le nouveau password OK
- [ ] Dashboard affiche l'onboarding progressif (jusqu'à la 1re quittance, FEAT-058)
- [ ] Étape 1 → `/properties/new` → créer un bien → retour dashboard OK
- [ ] Étape 2 → `/tenants/new` → créer un locataire → retour dashboard OK
- [ ] Étape 3 → `/leases/new` → créer un bail → retour dashboard OK
- [ ] Accueil → cockpit 3 zones affiché (À traiter / Mon patrimoine / Analyse)
- [ ] Naviguer vers le bail → enregistrer un paiement → KPI mis à jour
- [ ] Page quittances → générer une quittance PDF → preview s'ouvre OK
- [ ] Cliquer « Partager » → feuille de partage native s'ouvre → Mail/Gmail/WhatsApp → PDF + sujet + corps pré-remplis
- [ ] Uploader un document PDF de test → visible dans la liste
- [ ] **Simulateur** : créer et sauvegarder un scénario → il apparaît dans la liste (la création passe désormais par le callable `createScenario` ; l'écriture directe côté client est refusée par les règles — `investment_scenarios`)
- [ ] Dashboard → activité récente affiche le paiement + la quittance
- [ ] `/pro` affiche « Bientôt disponible » (abonnement coupé en prod : `SUBSCRIPTIONS_ENABLED=false`)
- [ ] Chrome desktop : PWA install prompt → « Installer » → app installée

---

## F. Vérifications post-deploy (48h)

- [ ] **Firebase Console** → Authentication : aucune erreur de connexion anormale
- [ ] **Cloud Logging** (`firebase functions:log`) : aucune erreur Cloud Functions
- [ ] **Firestore** → usage / erreurs de règles : rien d'anormal
- [ ] Reset password de bout en bout : email reçu + lien fonctionne
- [ ] Rafraîchissement forcé (Ctrl+Shift+R) : nouvelle version servie (pas de cache stale)

---

## G. Documentation

- [ ] `docs/state/FEATURES.md` : feature(s) marquée(s) ✅ déployée(s)
- [ ] `docs/state/INDEX.md` : timestamp mis à jour
- [ ] Équipe informée du go-live

---

## Rollback rapide si nécessaire

```bash
# Lister les versions du site prod
firebase hosting:versions:list --project easy-rent-54cd4

# Revenir à la version précédente sur le canal live
firebase hosting:clone easy-rent-54cd4:live easy-rent-54cd4:live \
  --version-id=<PREVIOUS_VERSION_ID>
```

**Si les règles bloquent des utilisateurs** (le rollback Hosting ci-dessus ne les annule pas) : redéployer les règles de la version précédente — `git checkout v1.0.0 -- firestore.rules firestore.indexes.json && firebase deploy --only 'firestore:(default)'`, et pour Storage `git checkout v1.0.0 -- storage.rules && firebase deploy --only storage` (⚠️ jamais `firestore` sans base cible ; détail dans le runbook §5). **Préparer ces commandes avant le merge.** Un rollback des règles v1.1.0 rouvre aussi les protections ajoutées depuis la v1.0.0 (champs Pro non modifiables côté client, scénarios, collections `charge_statements` / `etat_des_lieux`) : à n'utiliser que pour rétablir l'accès, puis corriger.

Détails et rollback backend : [`RUNBOOK_PROD_DEPLOY.md`](RUNBOOK_PROD_DEPLOY.md) §4–5.
