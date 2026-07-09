#!/usr/bin/env bash
#
# release.sh — coupe une release : crée le tag annoté vX.Y.Z (codename gravé
# dedans) + les notes de version, sans JAMAIS committer sur main (verrouillée).
#
# Le tag est la SEULE mutation git nécessaire pour publier une version — aucune
# ligne `version:` éditée, aucun commit de bump → zéro conflit d'auteur.
#
# Usage :
#   release.sh [major|minor|patch|auto]   (défaut : auto — déduit des commits)
#     --initial X.Y.Z   force le numéro de la toute première release
#     --push            pousse le tag vers origin
#     --gh-release      crée la GitHub Release (gh) — implique de pouvoir push
#     --notes-file      écrit aussi docs/releases/<tag>-<codename>.md (local)
#     --ci              mode non-interactif (configure git user, pas de prompt)
#
# Sans --push, tout reste LOCAL : le script affiche la commande de push à lancer.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$HERE/version.sh"
cd "$(git rev-parse --show-toplevel)"

BUMP="auto"; INITIAL=""; PUSH=0; GH=0; NOTES_FILE=0; CI=0
while [ $# -gt 0 ]; do
  case "$1" in
    major | minor | patch | auto) BUMP="$1" ;;
    --initial) INITIAL="${2:-}"; shift ;;
    --push) PUSH=1 ;;
    --gh-release) GH=1; PUSH=1 ;;
    --notes-file) NOTES_FILE=1 ;;
    --ci) CI=1 ;;
    -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "release.sh: argument inconnu : $1" >&2; exit 1 ;;
  esac
  shift
done

LAST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)"

if [ -n "$INITIAL" ]; then
  NAME="$INITIAL"
  CODENAME="$(bash "$VERSION" codename-next minor)"   # 1re essence disponible
else
  NAME="$(bash "$VERSION" next "$BUMP")"
  CODENAME="$(bash "$VERSION" codename-next "$BUMP")"
fi
CODE="$(git rev-list --count HEAD)"
TAG="v$NAME"
# Amorce (--initial ou aucun tag existant) → libellé "initial", sinon le bump
# effectif (major/minor/patch) résolu depuis les commits.
if [ -n "$INITIAL" ] || [ -z "$LAST_TAG" ]; then
  RESOLVED="initial"
else
  RESOLVED="$(bash "$VERSION" resolve-bump "$BUMP")"
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "release.sh: le tag $TAG existe déjà — rien à faire." >&2
  exit 1
fi

# Changelog = commits depuis le dernier tag (ou depuis le début si amorce).
RANGE="HEAD"
[ -n "$LAST_TAG" ] && RANGE="$LAST_TAG..HEAD"
CHANGES="$(git log --no-merges --pretty='- %s' "$RANGE" 2>/dev/null || true)"
[ -z "$CHANGES" ] && CHANGES="- (aucun commit listé)"
# Plafonne le changelog : sur l'amorce (v1.0.0) le range = tout l'historique
# (des centaines de commits) → on garde les CAP plus récents + un renvoi.
CAP=40
NCHANGES="$(printf '%s\n' "$CHANGES" | grep -c '^- ' || true)"
if [ "$NCHANGES" -gt "$CAP" ]; then
  CHANGES="$(printf '%s\n' "$CHANGES" | head -n "$CAP")
- … (+$((NCHANGES - CAP)) commits antérieurs — voir l'historique git)"
fi

TAG_MSG="$(printf '%s « %s »\n\nCodename: %s\nBuild: %s\nBump: %s\n\n%s\n' \
  "$TAG" "$CODENAME" "$CODENAME" "$CODE" "$RESOLVED" "$CHANGES")"

echo "──────────────────────────────────────────"
echo "  Release   : $TAG « $CODENAME »"
echo "  Build     : $CODE      (bump: $RESOLVED, précédent: ${LAST_TAG:-∅})"
echo "──────────────────────────────────────────"

if [ "$CI" -eq 1 ]; then
  git config user.name  "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
fi

git tag -a "$TAG" -m "$TAG_MSG"
echo "✓ tag annoté $TAG créé localement."

if [ "$NOTES_FILE" -eq 1 ]; then
  DIR="docs/releases"
  mkdir -p "$DIR"
  FILE="$DIR/${TAG}-$(echo "$CODENAME" | tr '[:upper:]' '[:lower:]' | tr -d 'çéèê ').md"
  # Heredoc plutôt que printf : le changelog commence par « - », ce qui ferait
  # planter `printf '- …'` (interprété comme une option). Les variables sont
  # substituées mais leur contenu n'est PAS ré-évalué (pas d'injection).
  cat > "$FILE" <<EOF
# $TAG « $CODENAME »

- **Build** : $CODE
- **Bump** : $RESOLVED
- **Date** : _(à compléter au tag)_

## Changements

$CHANGES
EOF
  echo "✓ notes de version : $FILE (à committer via develop, PAS sur main)."
fi

if [ "$PUSH" -eq 1 ]; then
  git push origin "$TAG"
  echo "✓ tag $TAG poussé sur origin."
else
  echo "ℹ️  local seulement. Pour publier :  git push origin $TAG"
fi

if [ "$GH" -eq 1 ]; then
  if command -v gh >/dev/null 2>&1; then
    printf '%s\n' "$TAG_MSG" | gh release create "$TAG" \
      --title "$TAG « $CODENAME »" --notes-file - --verify-tag
    echo "✓ GitHub Release $TAG créée."
  else
    echo "⚠️  gh introuvable — GitHub Release non créée."
  fi
fi
