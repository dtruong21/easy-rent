#!/usr/bin/env bash
#
# version.sh — dérive la version de l'app depuis l'historique git.
#
# SOURCE DE VÉRITÉ = les tags annotés `vX.Y.Z` sur main. Rien n'est stocké
# dans un fichier édité par branche (ni la ligne `version:` de pubspec, ni un
# CHANGELOG), donc AUCUN conflit de merge possible sur un numéro de version :
# tout est *dérivé* au moment du build.
#
#   - build-name / versionName / CFBundleShortVersionString = X.Y.Z (dernier tag)
#   - build-number / versionCode / CFBundleVersion          = nb de commits (monotone)
#   - codename                                              = essence d'arbre (gravée dans le tag)
#
# Le numéro de build (`git rev-list --count HEAD`) est strictement croissant
# tant que l'historique n'est pas réécrit (main est verrouillée, pas de
# force-push) → satisfait POUR TOUJOURS la contrainte des stores (chaque upload
# doit avoir un build strictement supérieur au précédent).
#
# Usage :
#   version.sh name              # X.Y.Z
#   version.sh code              # entier monotone (build number)
#   version.sh codename          # nom d'arbre de la version courante
#   version.sh full              # "X.Y.Z+CODE (Codename)"
#   version.sh env               # VERSION_NAME=… / VERSION_CODE=… / VERSION_CODENAME=…
#   version.sh next  [bump]      # PROCHAINE version (sans créer de tag)
#   version.sh codename-next [bump]  # codename de la prochaine version
#   version.sh resolve-bump [bump]   # major|minor|patch effectif (résout "auto")
#
#   bump = major | minor | patch | auto (défaut : auto = déduit des commits
#          conventionnels depuis le dernier tag : "feat" → minor, "!"/BREAKING
#          → major, sinon → patch).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREES_FILE="$HERE/codenames.txt"

# Toutes les commandes git + la lecture du pubspec supposent la racine du repo.
cd "$(git rev-parse --show-toplevel)"

die() { echo "version.sh: $*" >&2; exit 1; }

# Dernier tag de version atteignable depuis HEAD (chaîne vide si aucun).
latest_tag() {
  git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true
}

# Numéro de build : nombre total de commits ancêtres de HEAD.
build_code() { git rev-list --count HEAD; }

# Version du pubspec (X.Y.Z), sert d'amorce pour la toute première release.
pubspec_version() {
  grep -m1 '^version:' pubspec.yaml \
    | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
}

# Liste des codenames (hors commentaires et lignes vides), un par release.
codename_at() {
  local idx="$1" name
  name="$(grep -vE '^[[:space:]]*(#|$)' "$TREES_FILE" | sed -n "$((idx + 1))p")"
  # Filet de sécurité si la liste est épuisée : suffixe numéroté.
  [ -n "$name" ] && echo "$name" || echo "Séquoia-$idx"
}

# Nombre de lignes mineures déjà publiées (= nb de tags vX.Y.0).
minor_release_count() { git tag -l 'v[0-9]*.[0-9]*.0' | wc -l | tr -d ' '; }

# Codename gravé dans l'annotation d'un tag (ligne "Codename: …").
codename_from_tag() {
  [ -n "${1:-}" ] || return 0
  git tag -l --format='%(contents)' "$1" 2>/dev/null \
    | sed -n 's/^Codename:[[:space:]]*//p' | head -n1
}

# Codename effectif de la version courante (dernier tag), avec repli.
current_codename() {
  local tag cn
  tag="$(latest_tag)"
  cn="$(codename_from_tag "$tag")"
  [ -n "$cn" ] && { echo "$cn"; return; }
  # Aucun tag / annotation sans codename → 1re essence.
  codename_at 0
}

# Résout "auto" en major|minor|patch d'après les commits conventionnels.
resolve_bump() {
  local bump="${1:-auto}"
  [ "$bump" != auto ] && { echo "$bump"; return; }
  local tag range
  tag="$(latest_tag)"
  range="HEAD"
  [ -n "$tag" ] && range="$tag..HEAD"
  local subjects bodies
  subjects="$(git log --format='%s' "$range" 2>/dev/null || true)"
  bodies="$(git log --format='%B' "$range" 2>/dev/null || true)"
  if printf '%s\n%s\n' "$subjects" "$bodies" \
       | grep -qE 'BREAKING[ -]CHANGE|^[a-z]+(\([^)]*\))?!:'; then
    echo major
  elif printf '%s\n' "$subjects" | grep -qE '^[[:space:]]*feat(\([^)]*\))?:'; then
    echo minor
  else
    echo patch
  fi
}

# PROCHAINE version X.Y.Z sans créer de tag.
next_version() {
  local tag; tag="$(latest_tag)"
  # Amorce : la toute première release reprend la version du pubspec (ex.
  # 1.0.0), sans bump — on ne « saute » pas la 1.0.0 du lancement.
  [ -z "$tag" ] && { pubspec_version; return; }
  local bump major minor patch
  bump="$(resolve_bump "${1:-auto}")"
  IFS=. read -r major minor patch <<<"${tag#v}"
  case "$bump" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    *) die "bump inconnu : $bump" ;;
  esac
}

# Codename de la prochaine release.
next_codename() {
  local tag; tag="$(latest_tag)"
  [ -z "$tag" ] && { codename_at 0; return; }   # amorce → 1re essence
  local bump; bump="$(resolve_bump "${1:-auto}")"
  case "$bump" in
    major | minor) codename_at "$(minor_release_count)" ;; # essence suivante
    patch) current_codename ;;                             # réutilise la ligne
  esac
}

case "${1:-full}" in
  name) next_tag="$(latest_tag)"; [ -n "$next_tag" ] && echo "${next_tag#v}" || pubspec_version ;;
  code) build_code ;;
  codename) current_codename ;;
  full) echo "$( { t="$(latest_tag)"; [ -n "$t" ] && echo "${t#v}" || pubspec_version; } )+$(build_code) ($(current_codename))" ;;
  env)
    t="$(latest_tag)"; nm="$( [ -n "$t" ] && echo "${t#v}" || pubspec_version )"
    echo "VERSION_NAME=$nm"
    echo "VERSION_CODE=$(build_code)"
    echo "VERSION_CODENAME=$(current_codename)"
    ;;
  next) next_version "${2:-auto}" ;;
  codename-next) next_codename "${2:-auto}" ;;
  resolve-bump) resolve_bump "${2:-auto}" ;;
  *) die "commande inconnue : ${1:-} (voir l'en-tête du script)" ;;
esac
