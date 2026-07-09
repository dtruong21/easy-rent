# EasyRent — Versioning & releases

Version **dérivée de git**, jamais éditée à la main. Web + iOS + Android
partagent le même numéro. Chaque release porte un **codename d'arbre**.

## TL;DR

| Ce qu'on veut | Comment |
|---|---|
| Numéro de version | `git tag vX.Y.Z` sur `main` (source de vérité) |
| Numéro de build (stores) | `git rev-list --count HEAD` — monotone à vie |
| Nom lisible | codename = essence d'arbre, ordre alphabétique |
| Publier | **push sur `main`** → CI tague + release automatiquement |

## Schéma : `MAJOR.MINOR.PATCH` + codename

- **MAJOR** — rupture / jalon (ex. lancement public → `1.0.0`).
- **MINOR** — nouvelle(s) feature(s). **Nouveau codename.**
- **PATCH** — correctif (hotfix). **Garde le codename** de sa ligne mineure.

Le **build number** (versionCode Android / CFBundleVersion iOS / build web) =
nombre de commits ancêtres de `HEAD`. Comme `main` est verrouillée et sans
force-push, il ne fait que croître → **chaque upload store a un numéro
strictement supérieur au précédent**, pour toujours, sans compteur à tenir.

## Pourquoi « dériver » et pas éditer `pubspec.yaml`

`main` est **verrouillée** (cf. [`GITFLOW.md`](GITFLOW.md)) : la CI ne peut pas
y pousser un commit de bump. Et si chaque branche éditait la ligne `version:`,
on aurait des **conflits de merge permanents** sur ce numéro. On ne stocke donc
**rien** : tout est calculé au build depuis les tags + l'historique. `pubspec.yaml`
garde une valeur placeholder ignorée par la CI.

## Codenames — arbres, alphabétiques, sans conflit

La liste ordonnée vit dans [`tool/release/codenames.txt`](../tool/release/codenames.txt).
La release nº _n_ prend la _n_-ième essence : `Alisier`, `Aulne`, `Bouleau`, …
L'index est **déterministe** (= nombre de tags `vX.Y.0` déjà publiés), calculé
sur `main` de façon sérialisée → **personne ne réserve un nom, aucun conflit
d'auteur**. Le codename est gravé dans l'annotation du tag et le titre de la
GitHub Release. Pour en ajouter : uniquement **à la fin** du fichier.

## Le flux (branché sur Git Flow)

```
feature/* ──▶ develop ──▶ (push main) ──▶ CI Deploy prod
                                             ├─ build --build-name/--build-number (dérivés)
                                             ├─ deploy Firebase live
                                             └─ tag vX.Y.Z + GitHub Release   ← auto
```

- **develop → staging** : build avec la dernière version publiée + un build
  number plus haut (identifie le build). **Aucun tag.**
- **main → prod** : la CI calcule la prochaine version (bump déduit des commits
  conventionnels `feat`/`fix`/`!`), build, déploie, **puis** crée le tag annoté
  et la GitHub Release. Voir [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml).

Détection du bump (depuis le dernier tag) : `!:` ou `BREAKING CHANGE` → **major** ;
un `feat:` → **minor** ; sinon → **patch**. Première release = version du
pubspec (ex. `1.0.0`), sans bump.

## Outils

```bash
tool/release/version.sh name          # X.Y.Z affiché
tool/release/version.sh code          # build number (nb de commits)
tool/release/version.sh codename      # essence courante
tool/release/version.sh full          # "X.Y.Z+CODE (Codename)"
tool/release/version.sh next  [bump]  # prochaine version (sans taguer)

tool/release/release.sh [major|minor|patch|auto]   # coupe une release
  --push          pousse le tag
  --gh-release    crée la GitHub Release (implique --push)
  --notes-file    écrit docs/releases/<tag>-<codename>.md (à committer via develop)
  --initial X.Y.Z force le numéro de la 1re release
```

Sans `--push`, `release.sh` reste **local** (crée juste le tag) et affiche la
commande de push. En temps normal on ne l'appelle pas à la main : **push sur
`main` suffit**, la CI s'en charge.

## Historique des releases

Les notes détaillées sont les **GitHub Releases** (hors dépôt, donc pas de
commit sur `main`). Un miroir optionnel peut vivre dans
[`docs/releases/`](releases/) (généré par `--notes-file`, committé via `develop`).
