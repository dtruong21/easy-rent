# Checklist — Déploiement production Baillan/EasyRent

> Cocher chaque item avant / pendant / après le déploiement.
> Durée estimée : ~30 min (smoke test) + provisionnement initial la 1ère fois.
> Dernière mise à jour : 2026-07-24. Backend **100 % Firebase** (Firestore, Auth, Storage, Cloud Functions, Hosting).

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
- [ ] Providers activés : **Email/Password**, **Google**, **Apple**, **Anonymous**
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
- [ ] `cd functions && npm ci && npm run build && firebase deploy --only functions` (si functions changées)
- [ ] Rules Storage : **auto** par `deploy.yml` depuis `main` uniquement (cible `storage`, bucket partagé) — vérifier l'étape dans le run, puis **téléverser un document sur prod ET sur staging juste après le déploiement** (compte non anonyme à email vérifié ; un échec = règles Storage ou email non vérifié)

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
- [ ] **Google / Apple** : connexion via un provider social → OK
- [ ] **Mauvais password** : password incorrect → message « Email ou mot de passe incorrect » + email conservé
- [ ] **Reset password** : `/forgot-password` → email reçu → lien → `/reset-password` → nouveau password → redirect `/login` + snackbar → login avec le nouveau password OK
- [ ] Dashboard affiche l'onboarding « Premiers pas » (3 étapes)
- [ ] Étape 1 → `/properties/new` → créer un bien → retour dashboard OK
- [ ] Étape 2 → `/tenants/new` → créer un locataire → retour dashboard OK
- [ ] Étape 3 → `/leases/new` → créer un bail → retour dashboard OK
- [ ] Dashboard → 4 KPI cards affichées (loyers, retards, renouvellements, docs)
- [ ] Naviguer vers le bail → enregistrer un paiement → KPI mis à jour
- [ ] Page quittances → générer une quittance PDF → preview s'ouvre OK
- [ ] Cliquer « Partager » → feuille de partage native s'ouvre → Mail/Gmail/WhatsApp → PDF + sujet + corps pré-remplis
- [ ] Uploader un document PDF de test → visible dans la liste
- [ ] Dashboard → activité récente affiche le paiement + la quittance
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

Détails et rollback backend : [`RUNBOOK_PROD_DEPLOY.md`](RUNBOOK_PROD_DEPLOY.md) §4–5.
