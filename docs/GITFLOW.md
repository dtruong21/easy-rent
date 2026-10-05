# EasyRent — Git Flow simplifié

## 🌳 Modèle de branches

```
main          ──●──────●──────●──→   (PROD — Firebase live, schéma public)
                 ╲     ╱   ╲   ╱
                  release│   hotfix│
                  merge  │   merge │
                         ╲          ╲
develop       ──●─●─●─●──●─●─●─●──●─●──→  (DEV — Firebase staging, schéma dev)
                 ╲ ╲ ╱ ╱
                  feat/*     (branches courtes — depuis develop)
```

### Branches long-lived

| Branche | Rôle | Cible Hosting | URL | `APP_ENV` |
|---|---|---|---|---|
| `main` | Prod stable | `prod` | https://baillan.com | `prod` |
| `develop` | Intégration dev/staging | `stage` | https://app.staging.baillan.com | `dev` |

> Les deux cibles vivent dans le **même** projet Firebase et partagent donc
> Firestore, Auth et Storage — la séparation est purement Hosting. Détail et
> conséquences : [`ENVIRONMENTS.md`](ENVIRONMENTS.md).

### Branches éphémères

| Préfixe | Source | Destination | Quand |
|---|---|---|---|
| `feat/<slug>` | `develop` | `develop` (PR) | Nouvelle fonctionnalité |
| `fix/<slug>` | `develop` | `develop` (PR) | Bug non-urgent |
| `hotfix/<slug>` | `main` | `main` + `develop` (cherry-pick ou re-PR) | Bug critique en prod |
| `chore/<slug>` | `develop` | `develop` (PR) | Maintenance, refacto |
| `docs/<slug>` | `develop` | `develop` (PR) | Documentation seule |

> Préfixes alignés sur les types de commits conventionnels (`feat:`, `fix:`,
> `chore:`, `docs:`). Les branches antérieures à juillet 2026 utilisaient
> `feature/…` — les documents d'historique (plans, ADR) gardent ces noms tels
> quels, ce sont des enregistrements de ce qui s'est passé.

## 🧹 Hygiène des branches distantes

- Une branche éphémère se supprime **dès que sa PR est mergée**. Activer
  Settings → General → **Automatically delete head branches** pour que GitHub
  le fasse seul.
- Les merges `feat/fix/chore → develop` sont des **squash** : `git branch -r
  --merged` ne détecte donc pas ces branches. Vérifier l'état de la PR avant de
  supprimer une branche « non mergée ».
- Audit : `git fetch --prune`, puis `git branch -r --merged origin/develop` et
  `--merged origin/main` (sûrs à supprimer), puis `git push origin --delete <branche>`.
  Ne jamais supprimer `main`, `develop` ni une branche liée à une PR ouverte.

### À faire à la prochaine session (audit du 2026-10-03, mis à jour le 2026-10-04)

Fait : 33 branches mergées supprimées le 2026-10-03, puis
`claude/amazing-ardinghelli-29501a`, `claude/nice-grothendieck-c66baf`,
`feat/056-multi-tier-subscriptions` et `claude/magical-jackson-d0116a` (contenu déjà dans
`develop` ou repris par la PR #211) — confirmé par `git fetch --prune`. Reste :

1. **Supprimer** (PR mergées — pointe = tête de PR) : `chore/cleanup-cards-feat-059` (#217),
   `chore/followup-pr-200` (#218), `docs/store-forms-signin-v1` (#219),
   `docs/ios27-sdk-audit` (#212), `feat/auth-providers-v1` (#214),
   `docs/state-refresh-functions` (#222, mergée le 2026-10-05),
   `fix/billing-robustness-209` (#221) et `fix/ux-mobile-recette-ios` (#220), mergées le 2026-10-05 (pointes = tête de PR),
   `docs/security-stripe-resolvers` (#216, mergée le 2026-10-05).
   Déjà supprimées : `chore/restore-mobile-release-files` (#211),
   `fix/summary-card-key-figure-overflow` (#210), `fix/summary-card-keyfigure-overflow`
   (#213 fermée), `fix/stripe-guard-accept-resolvers` (#215 fermée).
   Un `git push --delete` groupé est rejeté en bloc si une des refs n'existe plus :
   relancer après un `git fetch --prune`, avec uniquement les refs restantes.
2. **Garder** : `main`, `develop`, `chore/050e-bascule-domaine` (PR #162 ouverte, à ne pas
   merger avant le DNS).
3. **Côté stores** (suites de #211 et #219) : note « remplacé par #214 » à ajouter dans
   `STORE_COMPLIANCE.md` lignes 34–35 (test iOS 27 daté, antérieur à #214) ; URLs privacy / delete-account
   (`easy-rent-54cd4.web.app` → `app.baillan.com` avec #162), question « Achats numériques » — **vérifiée le 2026-10-05** : le paywall n'est PAS atteignable
   depuis les apps iOS/Android (`isStoreApp` masque Stripe, prix et boutons ; `/pro` n'y affiche que
   « offres payantes pas encore proposées » ; tests dédiés) ; **en cours (PR #224)** : 4 messages d'erreur « Passez à
   l'offre Pro / à {palier} » visibles aussi sur mobile (limites biens / locataires / baux, taille de document,
   `app_fr.arb`) — texte seul, sans lien, variantes sans appel sur `isStoreApp` dans la PR #224 ; la modale du simulateur
   (`simulatorLimitReachedContent*`) garde volontairement son texte, à trancher — et la règle Apple 3.1.3(b)
   (accès multiplateforme à ce qui est acheté sur le web) à vérifier dans les règles en vigueur, re-vérification des règles des stores.
4. Activer *Automatically delete head branches* (voir ci-dessus).

> Les branches de l'ancien historique (`claude/*`, `feature/*`) n'ont aucun ancêtre commun
> avec `develop` (historique réécrit) : comparer par contenu, pas par `git log`.

## 🔒 Branch protection (à configurer sur GitHub)

Pour les deux long-lived branches (`main` et `develop`) — Settings → Branches → Add branch protection rule :

### Règles communes (main + develop)
- ✅ **Require a pull request before merging**
- ✅ **Require approvals** : 1 (peut être toi-même via review automatique des agents)
- ✅ **Require status checks** : `analyze-test` du workflow CI
- ✅ **Require branches to be up to date before merging**
- ❌ **Allow force pushes** : NEVER
- ❌ **Allow deletions** : NEVER

### Règles spécifiques à `main`
- ✅ **Require linear history** (oblige squash ou rebase, pas de merge commits messy)
- ✅ **Lock branch** : impossible de pousser directement, même par admin
- ✅ **Restrict who can push** : personne (uniquement via PR depuis `develop`)

## 🔄 Workflows quotidiens

### Démarrer une nouvelle feature
```bash
git checkout develop
git pull
git checkout -b feat/quittance-pdf-mensuelle
# ... code ...
git push -u origin feat/quittance-pdf-mensuelle
gh pr create --base develop --head feat/quittance-pdf-mensuelle
```

Quand la PR est mergée → la feature arrive sur `develop` → CI build et déploie automatiquement sur **staging** (Firebase staging channel, schéma `dev`).

### Promouvoir develop vers prod (release)
Quand `develop` est stable et tu veux livrer en prod :
```bash
git checkout main
git pull
git merge --no-ff develop  # ou via PR develop → main
git push origin main
```
→ CI déploie sur **prod** (Firebase live channel, schéma `public`).

### Hotfix sur prod
Bug urgent en prod, pas le temps de passer par develop :
```bash
git checkout main
git pull
git checkout -b hotfix/auth-bypass
# ... fix ...
gh pr create --base main
# Après merge sur main, propager vers develop :
git checkout develop
git pull
git merge main
git push origin develop
```

## 🎯 Conventions de commit

Format : `<type>(<scope>): <description>`

| Type | Quand |
|---|---|
| `feat` | Nouvelle fonctionnalité |
| `fix` | Correction de bug |
| `chore` | Maintenance, dépendances |
| `docs` | Documentation seule |
| `test` | Ajout/modif de tests |
| `refactor` | Refacto sans changement fonctionnel |
| `perf` | Optimisation perf |

Scope : `auth`, `properties`, `tenants`, `leases`, `payments`, `pdf`, `ui`, `db`, etc.

Exemples :
- `feat(quittance): générer PDF avec mentions légales loi 89`
- `fix(auth): corriger redirect après magic link`
- `chore(deps): bump firebase_auth to 5.3.1`

## 🔀 Strategy de merge

- **feature → develop** : **Squash merge** (PR = 1 commit propre dans develop)
- **develop → main** : **Merge commit** (`--no-ff`) — préserve l'historique des releases
- **hotfix → main** : **Squash merge**
- **main → develop** (back-merge après hotfix) : **Merge commit**

## 🤖 Comment les agents IA interagissent

| Agent / Commande | Source branch | Target branch |
|---|---|---|
| `/build-feature` | `develop` | crée `feat/*`, PR vers `develop` |
| `/fix-bug` (non-urgent) | `develop` | crée `fix/*`, PR vers `develop` |
| `/fix-bug` (hotfix label) | `main` | crée `hotfix/*`, PR vers `main` |
| `ticket-agent.yml` | `develop` | crée branches, PR vers `develop` |

## 🏷️ Versioning (branché sur ce flow)

Chaque push sur `main` = une **release** taguée automatiquement par la CI.
Rien à éditer à la main : la version est **dérivée de git** et le tag `vX.Y.Z`
(+ GitHub Release) est créé après un deploy prod réussi. Détail complet :
[`docs/VERSIONING.md`](VERSIONING.md).

- Bump déduit des commits conventionnels ci-dessous : `feat` → **minor** (+ nouveau
  codename d'arbre), `fix`/reste → **patch** (garde le codename), `!`/`BREAKING
  CHANGE` → **major**.
- Build number = nb de commits (monotone) → uploads stores jamais rejetés.
- `main` verrouillée ⇒ la CI ne pousse **qu'un tag** (aucun commit de bump,
  aucun conflit de version).

## ✅ Avant de promouvoir develop → main

Checklist obligatoire :
- [ ] Toutes les features du sprint sont mergées dans develop
- [ ] CI verte sur develop
- [ ] Staging testé manuellement (smoke tests : auth + créer un bien + envoyer une quittance)
- [ ] Pas de migration DB cassante non préparée
- [ ] Confirmation utilisateur explicite (jamais auto-promote en prod)
- [ ] (Le tag `vX.Y.Z` + la GitHub Release sont créés **automatiquement** par la
      CI au push sur `main` — voir [`docs/VERSIONING.md`](VERSIONING.md))
