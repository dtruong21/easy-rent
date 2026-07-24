#!/usr/bin/env bash
# Garde-fou ADR 0003 — isolation Firestore prod/staging.
#
# Interdit l'accès direct à la base Firestore hors des points de routage
# centralisés :
#   - Flutter  → `firestoreProvider` (lib/core/config/firestore_provider.dart)
#   - Functions → `dbForRequest` / `dbForLandlordUid` (functions/src/utils/db_router.ts)
#
# Sans ce garde-fou, un dev qui retape `FirebaseFirestore.instance` ou
# `admin.firestore()` fait fuir l'isolation : une écriture staging atterrit en
# prod. Voir docs/adr/0003-firestore-prod-staging-isolation.md.
set -euo pipefail
fail=0

# --- Flutter : FirebaseFirestore.instance interdit hors provider + main.dart ---
# `instanceFor(...)` autorisé (utilisé PAR le provider) ; le câblage émulateur
# de main.dart autorisé ; les lignes de commentaire (///) ignorées.
flutter_bad=$(grep -rnE "FirebaseFirestore\.instance\b" lib/ \
  | grep -vE "lib/core/config/firestore_provider.dart|lib/main.dart" \
  | grep -vE ":[0-9]+:[[:space:]]*///" || true)
if [ -n "$flutter_bad" ]; then
  echo "❌ Accès Firestore direct interdit dans lib/ — passer par firestoreProvider :"
  echo "$flutter_bad"
  fail=1
fi

# --- Functions : admin.firestore() / getFirestore() interdits dans le code
# piloté par requête (callable/ + http/) — router via dbForRequest /
# dbForLandlordUid. Les crons (scheduled/) et triggers Firestore restent sur
# (default) volontairement (pas de notion d'environnement pour eux).
fn_bad=$(grep -rnE "admin\.firestore\(\)|getFirestore\(" \
  functions/src/callable/ functions/src/http/ 2>/dev/null || true)
if [ -n "$fn_bad" ]; then
  echo "❌ Accès Firestore direct interdit dans functions/src/{callable,http}/ — router via db_router :"
  echo "$fn_bad"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "✅ Isolation Firestore (ADR 0003) respectée."
fi
exit "$fail"
