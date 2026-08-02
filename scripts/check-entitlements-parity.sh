#!/usr/bin/env bash
# Garde-fou FEAT-056 — parité de la table de droits (plan §2.2).
#
# Risque couvert (R1) : le client autorise ce que le serveur refuse, ou
# l'inverse. La grille de droits existait jusqu'ici en QUATRE exemplaires
# recopiés à la main. Elle a désormais une source canonique unique,
# `config/entitlements.json`, d'où sont GÉNÉRÉS les deux miroirs :
#
#   Dart : lib/features/auth/domain/plan_matrix.g.dart
#   TS   : functions/src/entitlements/plan_matrix.generated.ts
#
# Ce script relance les deux générateurs et fait échouer la PR si :
#   1. un miroir généré est périmé (JSON modifié sans régénération) ;
#   2. un miroir a été édité À LA MAIN (le diff le révèle) ;
#   3. les deux miroirs ne portent pas le MÊME sourceSha (générateur cassé) ;
#   4. le sourceSha embarqué ne correspond pas au JSON réellement présent ;
#   5. la table est invalide (trou dans un quota, palier vendable sans
#      entitlement RevenueCat, marqueur « À DÉFINIR », etc.) — les deux
#      générateurs valident et sortent en erreur.
#
# Convention identique à scripts/check-db-isolation.sh : un script shell,
# exit != 0 = PR rouge.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SOURCE="config/entitlements.json"
DART_OUT="lib/features/auth/domain/plan_matrix.g.dart"
TS_OUT="functions/src/entitlements/plan_matrix.generated.ts"

fail() {
  echo "❌ $1"
  exit 1
}

[ -f "$SOURCE" ] || fail "source canonique introuvable : $SOURCE"
command -v dart >/dev/null 2>&1 || fail "dart introuvable sur le PATH"
command -v node >/dev/null 2>&1 || fail "node introuvable sur le PATH"

# --- 1. JSON bien formé (avant même de lancer les générateurs, pour un
# message d'erreur lisible plutôt qu'une stack trace).
node -e "JSON.parse(require('fs').readFileSync('$SOURCE','utf8'))" \
  || fail "$SOURCE n'est pas du JSON valide (rappel : JSON STRICT, pas de commentaires)"

# --- 2. Snapshot AVANT régénération. On compare au contenu présent dans
# l'arbre de travail, pas à `git diff` : un fichier généré encore non suivi
# par git (branche de feature en cours) échapperait sinon complètement au
# contrôle, qui ne mordrait qu'après le premier commit.
SNAPSHOT_DIR=$(mktemp -d)
trap 'rm -rf "$SNAPSHOT_DIR"' EXIT
[ -f "$DART_OUT" ] && cp "$DART_OUT" "$SNAPSHOT_DIR/dart.before"
[ -f "$TS_OUT" ] && cp "$TS_OUT" "$SNAPSHOT_DIR/ts.before"

# --- 3. Régénération des deux miroirs (chaque générateur valide la table et
# sort en erreur si elle est incomplète).
dart run tool/gen_entitlements.dart >/dev/null \
  || fail "génération Dart échouée (voir le message ci-dessus)"
node functions/tool/gen_entitlements.mjs >/dev/null \
  || fail "génération TypeScript échouée (voir le message ci-dessus)"

# --- 4. Miroirs à jour ? Une différence ici = fichier généré édité à la main,
# ou JSON modifié sans régénération.
stale=0
for pair in "$DART_OUT:dart.before" "$TS_OUT:ts.before"; do
  out="${pair%%:*}"
  before="$SNAPSHOT_DIR/${pair##*:}"
  if [ ! -f "$before" ]; then
    echo "❌ Miroir généré absent avant régénération : $out (à committer)"
    stale=1
  elif ! diff -q "$before" "$out" >/dev/null; then
    echo "❌ Miroir généré périmé ou édité à la main : $out"
    diff -u "$before" "$out" | head -40 || true
    stale=1
  fi
done
if [ "$stale" -ne 0 ]; then
  echo
  echo "   Corriger : éditer UNIQUEMENT $SOURCE, puis"
  echo "     dart run tool/gen_entitlements.dart"
  echo "     node functions/tool/gen_entitlements.mjs"
  exit 1
fi

# --- 5. Les deux miroirs portent-ils le même sourceSha, et est-ce bien celui
# du JSON présent dans l'arbre ?
# `dart format` peut replier la déclaration sur deux lignes → on aplatit le
# fichier avant d'extraire, sinon le motif ne matche plus une fois le SHA
# renvoyé à la ligne suivante.
dart_sha=$(tr -d '\n' < "$DART_OUT" \
  | sed -n "s/.*sourceSha *= *'\([0-9a-f]\{64\}\)'.*/\1/p")
ts_sha=$(tr -d '\n' < "$TS_OUT" \
  | sed -n 's/.*PLAN_MATRIX_SOURCE_SHA *= *"\([0-9a-f]\{64\}\)".*/\1/p')
json_sha=$(node -e "
  const {createHash} = require('crypto');
  const fs = require('fs');
  process.stdout.write(createHash('sha256').update(fs.readFileSync('$SOURCE')).digest('hex'));
")

[ -n "$dart_sha" ] || fail "sourceSha introuvable dans $DART_OUT"
[ -n "$ts_sha" ] || fail "sourceSha introuvable dans $TS_OUT"

if [ "$dart_sha" != "$ts_sha" ]; then
  fail "sourceSha divergents — Dart=$dart_sha TS=$ts_sha (un générateur est cassé)"
fi
if [ "$dart_sha" != "$json_sha" ]; then
  fail "sourceSha ($dart_sha) != SHA-256 réel de $SOURCE ($json_sha)"
fi

echo "✅ Table de droits : miroirs Dart/TS à jour et cohérents (sourceSha ${dart_sha:0:12}…)."
