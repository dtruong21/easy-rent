#!/usr/bin/env bash
# Garde-fou issue #138 — isolation Stripe prod/staging.
#
# Interdit la lecture directe des secrets Stripe hors du résolveur centralisé
# `resolveStripeKeyOrThrow` (functions/src/utils/stripe_env.ts), seule porte
# vers la clé `sk_live`.
#
# Sans ce garde-fou, un dev qui retape `stripeSecret.value()` dans une nouvelle
# callable rouvre #138 en silence : la fonction sert la clé live à un appel
# venu de staging, et un test du paywall encaisse de l'argent réel. Les tests
# unitaires du résolveur ne l'attrapent pas — ils verrouillent la DÉCISION, pas
# le fait que chaque appelant passe bien par elle.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

fail=0

# `.value()` sur un secret Stripe est réservé à deux endroits : la déclaration
# du secret elle-même, et l'appel qui passe les deux clés au résolveur. On
# repère l'usage interdit par la ligne qui lit un secret Stripe SANS que
# `resolveStripeKeyOrThrow` apparaisse dans le même fichier.
for f in $(grep -rlE "stripe(Test)?Secret\.value\(\)" functions/src/ \
    --include="*.ts" 2>/dev/null | grep -v "__tests__" || true); do
  if ! grep -q "resolveStripeKeyOrThrow" "$f"; then
    echo "❌ Secret Stripe lu sans passer par resolveStripeKeyOrThrow : $f"
    fail=1
  fi
done

# `new Stripe(...)` ne doit jamais recevoir un secret directement : la clé doit
# venir du résolveur, qui refuse les origines inconnues.
stripe_bad=$(grep -rnE "new Stripe\([[:space:]]*stripe(Test)?Secret" functions/src/ \
  --include="*.ts" 2>/dev/null | grep -v "__tests__" || true)
if [ -n "$stripe_bad" ]; then
  echo "❌ Client Stripe construit sur un secret brut — passer par resolveStripeKeyOrThrow :"
  echo "$stripe_bad"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "✅ Isolation Stripe (issue #138) respectée."
fi
exit "$fail"
