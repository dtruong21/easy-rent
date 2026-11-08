#!/usr/bin/env bash
# Garde-fou — l'URL du formulaire d'idées doit être un vrai formulaire Tally
# avant un build de PRODUCTION. Le placeholder `https://tally.so/` (racine)
# est toléré en staging (SITE_ENV=staging) mais refusé en prod.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ "${SITE_ENV:-}" = "staging" ]; then
  echo "ℹ️  SITE_ENV=staging — placeholder Tally toléré."
  exit 0
fi

url=$(grep -oE "ideaFormUrl = '[^']*'" site/src/lib/links.ts | sed "s/.*= '//;s/'//" || true)

case "$url" in
  https://tally.so/|https://tally.so|"")
    echo "❌ ideaFormUrl est encore le placeholder ($url). Renseigner le vrai"
    echo "   formulaire Tally dans site/src/lib/links.ts avant un build de prod."
    exit 1 ;;
  https://tally.so/*)
    echo "✅ ideaFormUrl configuré ($url)." ; exit 0 ;;
  *)
    echo "❌ ideaFormUrl ne pointe pas vers tally.so ($url)." ; exit 1 ;;
esac
