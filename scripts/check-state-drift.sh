#!/usr/bin/env bash
# Détecteur de dérive du cache d'état (docs/state/) — coût ZÉRO token.
#
# Pourquoi : CLAUDE.md impose de lire `docs/state/<domaine>.md` plutôt que de
# grepper le code. Mais un shard périmé est PIRE que pas de shard : l'agent lui
# fait confiance, écrit du code faux, se fait bloquer, et refait le travail —
# donc bien plus de tokens qu'un grep honnête. Exemple réel (2026-07-30) : ADR
# 0003 mergée le 25/07 était absente de tous les shards, si bien qu'un agent
# aurait écrit `admin.firestore()` en direct et heurté check-db-isolation.sh.
#
# Ce script ne corrige RIEN et ne bloque JAMAIS (toujours exit 0). Il signale
# les domaines à rafraîchir, pour lancer `state-keeper` UNIQUEMENT sur ceux-là
# au lieu d'une passe complète (qui, elle, coûte cher).
#
# Silencieux quand tout est frais — c'est voulu : le cas normal doit coûter 0
# ligne de contexte. Il ne parle que s'il y a quelque chose à faire.
#
# Usage :
#   bash scripts/check-state-drift.sh          # seuil par défaut
#   bash scripts/check-state-drift.sh --hook   # sortie JSON pour hook SessionStart
#   STATE_DRIFT_THRESHOLD=1 bash scripts/...   # plus strict
#   STATE_DRIFT_VERBOSE=1 bash scripts/...     # affiche aussi les domaines OK
set -uo pipefail

HOOK_MODE=0
[ "${1:-}" = "--hook" ] && HOOK_MODE=1

cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || exit 0
[ -d docs/state ] || exit 0

# Nombre de commits touchant le code d'un domaine, depuis la dernière mise à
# jour de son shard, avant de crier. 1 ou 2 commits sont souvent cosmétiques ;
# à partir de 3 la probabilité d'une vraie divergence devient sérieuse.
THRESHOLD="${STATE_DRIFT_THRESHOLD:-3}"
VERBOSE="${STATE_DRIFT_VERBOSE:-0}"

DOMAINS="account dashboard expenses-documents leases payments-receipts properties simulator"

# Date du dernier commit touchant un chemin (epoch, 0 si inconnu/absent).
last_commit_epoch() {
  local e
  e=$(git log -1 --format=%ct -- "$@" 2>/dev/null)
  echo "${e:-0}"
}

stale_lines=""
fresh_lines=""

for d in $DOMAINS; do
  shards=""
  for kind in routes schema functions; do
    [ -f "docs/state/$kind/$d.md" ] && shards="$shards docs/state/$kind/$d.md"
  done
  [ -z "$shards" ] && continue

  shard_epoch=$(last_commit_epoch $shards)
  [ "$shard_epoch" = "0" ] && continue

  code_paths="lib/features/$d"
  [ -d "$code_paths" ] || continue

  # Commits de code postérieurs au shard. --since est exclusif de la seconde
  # exacte, ce qui évite de compter le commit du shard lui-même.
  n=$(git log --oneline --since="@$shard_epoch" -- "$code_paths" 2>/dev/null | wc -l | tr -d ' ')
  n="${n:-0}"

  if [ "$n" -ge "$THRESHOLD" ]; then
    days=$(( ( $(date +%s) - shard_epoch ) / 86400 ))
    stale_lines="${stale_lines}  ${d} — ${n} commits de code depuis le shard (${days}j)\n"
  else
    fresh_lines="${fresh_lines}  ${d} — ${n} commit(s), sous le seuil\n"
  fi
done

# Signaux transverses : ces fichiers-là changent la façon d'écrire du code dans
# TOUS les domaines, donc un shard qui les ignore fait écrire du code invalide.
cross=""
rules_epoch=$(last_commit_epoch firestore.rules firestore.indexes.json)
schema_epoch=$(last_commit_epoch docs/state/schema)
if [ "$rules_epoch" -gt "$schema_epoch" ] 2>/dev/null; then
  cross="${cross}  firestore.rules/indexes plus récents que docs/state/schema/\n"
fi

fn_epoch=$(last_commit_epoch functions/src)
fnshard_epoch=$(last_commit_epoch docs/state/functions)
if [ "$fn_epoch" -gt "$fnshard_epoch" ] 2>/dev/null; then
  cross="${cross}  functions/src/ plus récent que docs/state/functions/\n"
fi

# Garde-fou ADR 0003 : si le routage par base existe dans le code mais n'est pas
# décrit là où l'agent concerné va LIRE, il écrira un accès direct et se fera
# bloquer par check-db-isolation.sh.
#
# On vérifie que la règle est écrite là où elle sera EFFECTIVEMENT lue :
#  - `CLAUDE.md`, auto-chargé à chaque session → une règle transverse qui y
#    figure ne peut pas être manquée. C'est la place retenue pour celle-ci ;
#  - à défaut, un shard de DOMAINE (`functions/<d>.md`, `schema/<d>.md`, …).
#
# Volontairement PAS acceptés : `INDEX.md`, `CHANGELOG.md`, et les `README.md`
# de dossier. Un agent charge `schema/properties.md`, pas le panorama du dossier
# (règle d'or n°2) — une mention là-dedans ne l'atteint jamais. Ce garde-fou
# s'est fait tromper deux fois par exactement ça : une mention dans
# CHANGELOG.md, puis une dans schema/README.md, les deux invisibles pour l'agent
# censé appliquer la règle. D'où la liste blanche explicite ci-dessous.
domain_shards=$(find docs/state/functions docs/state/schema docs/state/routes \
  -name "*.md" ! -name "README.md" 2>/dev/null)

rule_documented() { # $1 = motif egrep
  grep -qE "$1" CLAUDE.md 2>/dev/null && return 0
  [ -n "$domain_shards" ] || return 1
  # shellcheck disable=SC2086
  grep -qE "$1" $domain_shards 2>/dev/null
}

if [ -f functions/src/utils/db_router.ts ] &&
   ! rule_documented "dbForRequest|db_router"; then
  cross="${cross}  db_router.ts existe mais absent de CLAUDE.md et des shards de domaine (ADR 0003)\n"
fi
if [ -f lib/core/config/firestore_provider.dart ] &&
   ! rule_documented "firestoreProvider"; then
  cross="${cross}  firestoreProvider existe mais absent de CLAUDE.md et des shards de domaine (ADR 0003)\n"
fi

report=""
if [ -n "$stale_lines" ] || [ -n "$cross" ]; then
  report="⚠️  Cache d'état probablement périmé (docs/state/) :\n"
  [ -n "$stale_lines" ] && report="${report}${stale_lines}"
  [ -n "$cross" ] && report="${report}${cross}"
  report="${report}   → rafraîchir CES domaines seulement : /refresh-state\n"
  report="${report}   (ne pas faire confiance aux shards listés ; vérifier le code pour eux)\n"
fi

if [ "$HOOK_MODE" = "1" ]; then
  # Mode hook SessionStart : silence total si l'état est frais (le cas normal
  # doit coûter 0 token). Sinon on injecte le rapport dans le contexte du
  # modèle via additionalContext — un simple echo ne l'y ferait pas entrer.
  # python3 (/usr/bin, pas homebrew) sérialise proprement accents et retours
  # ligne, ce qu'un montage de JSON à la main casserait.
  if [ -n "$report" ]; then
    printf "%b" "$report" | python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.stdin.read()}}))' 2>/dev/null || true
  fi
elif [ -n "$report" ]; then
  printf "%b" "$report"
elif [ "$VERBOSE" = "1" ]; then
  echo "✅ docs/state/ frais (seuil=$THRESHOLD commits)"
  printf "%b" "$fresh_lines"
fi

# Un détecteur ne casse jamais un workflow.
exit 0
