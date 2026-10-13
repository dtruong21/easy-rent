#!/usr/bin/env bash
# Tests de scripts/check-secrets.sh (#131) : chaque motif détecte une fausse
# clé réaliste, et les quasi-homonymes légitimes ne déclenchent rien.
#
# Les fausses clés sont ASSEMBLÉES à l'exécution (préfixe + corps) : elles
# n'apparaissent jamais en clair dans le dépôt, donc ce fichier n'a pas besoin
# d'être exclu du scan (et le scan --all de la CI le couvre comme le reste).
#
# Usage : bash scripts/test-check-secrets.sh   (lancé par la CI)

set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-secrets.sh"
BODY="AbCdEfGh12345678IjKlMnOp"   # 24 caractères alphanumériques
FAIL=0

# Dépôt jetable : le scanner lit les fichiers stagés du dépôt courant.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

run_scan() { # $1 = chemin relatif, $2 = contenu → code de sortie du scanner
  rm -rf "$WORK/repo" && mkdir -p "$WORK/repo" && cd "$WORK/repo" || exit 2
  git init -q .
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
  git add "$1"
  bash "$SCRIPT" > /dev/null 2>&1
  local code=$?
  cd - > /dev/null || exit 2
  return $code
}

expect_detected() { # $1 = libellé, $2 = fichier, $3 = contenu
  if run_scan "$2" "$3"; then
    echo "❌ NON détecté : $1"
    FAIL=1
  else
    echo "✅ détecté : $1"
  fi
}

expect_clean() { # $1 = libellé, $2 = fichier, $3 = contenu
  if run_scan "$2" "$3"; then
    echo "✅ ignoré (légitime) : $1"
  else
    echo "❌ FAUX POSITIF : $1"
    FAIL=1
  fi
}

# --- Nouveaux motifs (#131) -------------------------------------------------
expect_detected "Stripe sk_test_" config.ts "const k = \"sk_""test_$BODY\";"
expect_detected "Stripe rk_test_" config.ts "const k = \"rk_""test_$BODY\";"
expect_detected "Stripe sk_org_" config.ts "const k = \"sk_""org_$BODY\";"
expect_detected "Stripe whsec_" config.ts "STRIPE_WEBHOOK_SECRET=whsec_""$BODY"
expect_detected "RevenueCat sk_ (début de ligne)" .env "sk_""$BODY"
expect_detected "RevenueCat sk_ (après un =)" .env "REVENUECAT_API_KEY=sk_""$BODY"
expect_detected "clé collée dans docs/SECURITY.md (plus exclu)" \
  docs/SECURITY.md "Exemple réel par erreur : sk_""live_$BODY"

# --- Motifs existants (non-régression) --------------------------------------
expect_detected "Stripe sk_live_" config.ts "const k = \"sk_""live_$BODY\";"
expect_detected "Stripe rk_live_" config.ts "const k = \"rk_""live_$BODY\";"

# --- Quasi-homonymes légitimes ----------------------------------------------
expect_clean "identifiant « task_… » (sk_ en milieu de mot)" app.ts \
  "const task_""$BODY = 1;"
expect_clean "identifiant « mask_… »" app.ts "const mask_""$BODY = 1;"
expect_clean "fausse clé de test courte des tests (sk_test_fake)" test.ts \
  "const LIVE_KEY = \"sk_""test_fake\";"
expect_clean "doc abrégée (« sk_live_… »)" docs/SECURITY.md \
  "Les clés live commencent par sk_""live_…"
expect_clean "clé publique RevenueCat (SDK)" app.ts "const k = \"appl_""$BODY\";"

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "❌ test-check-secrets : échec"
  exit 1
fi
echo ""
echo "✅ test-check-secrets : tous les cas passent"
