#!/usr/bin/env bash
# Garde-fou issue #138 — isolation Stripe prod/staging.
#
# La clé `sk_live` ne doit être atteignable que par `resolveStripeKeyOrThrow`
# (functions/src/utils/stripe_env.ts). Sans ce garde-fou, un dev qui construit
# un client Stripe sur un secret brut rouvre #138 en silence : la fonction sert
# la clé live à un appel venu de staging, et un test du paywall encaisse de
# l'argent réel. Les tests unitaires ne l'attrapent pas — ils verrouillent la
# DÉCISION, pas le fait que chaque appelant passe bien par elle.
#
# ⚠️ Les règles portent sur ce qu'un dev ne peut PAS renommer : le constructeur
# `new Stripe(` et le nom du secret `STRIPE_...`. Une première version greppait
# le nom de la variable (`stripeSecret`) : renommer la constante suffisait à
# passer en vert, ce qui en faisait un garde-fou décoratif.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Un dossier absent ne doit pas produire un ✅ silencieux.
if [ ! -d functions/src ]; then
  echo "❌ functions/src/ introuvable — garde-fou Stripe inopérant."
  exit 1
fi

fail=0

# Fichiers exemptés : le résolveur lui-même et les tests.
is_exempt() {
  case "$1" in
    functions/src/utils/stripe_env.ts) return 0 ;;
    *__tests__*) return 0 ;;
    *) return 1 ;;
  esac
}

# Règle 1 — tout fichier qui construit un client Stripe doit passer par le
# résolveur.
#
# `IFS= read -r` (sans `-Z`/`-d ''`) : `$(...)` non quoté découperait les
# chemins contenant une espace en plusieurs faux fichiers, et `-Z` n'est pas
# portable — certains wrappers `grep` rendent quand même des lignes, la boucle
# n'itère alors sur RIEN et le script conclut ✅ sans avoir rien lu.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  is_exempt "$f" && continue
  if ! grep -q "resolveStripeKeyOrThrow" "$f"; then
    echo "❌ Client Stripe construit sans resolveStripeKeyOrThrow : $f"
    fail=1
  fi
done <<EOF
$(grep -rl --include="*.ts" "new Stripe(" functions/src/ 2>/dev/null || true)
EOF

# Règle 2 — tout fichier qui déclare ou lit un secret Stripe doit passer par le
# résolveur. Couvre `defineSecret("STRIPE_...")` ET `process.env.STRIPE_...`,
# les secrets v2 étant aussi exposés en variable d'environnement.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  is_exempt "$f" && continue
  if ! grep -q "resolveStripeKeyOrThrow" "$f"; then
    echo "❌ Secret Stripe atteint sans resolveStripeKeyOrThrow : $f"
    fail=1
  fi
done <<EOF
$(grep -rl --include="*.ts" -E 'defineSecret\("STRIPE_|process\.env\.STRIPE_' functions/src/ 2>/dev/null || true)
EOF

if [ "$fail" -eq 0 ]; then
  echo "✅ Isolation Stripe (issue #138) respectée."
fi
exit "$fail"
