#!/usr/bin/env bash
# Garde-fou ADR 0003 — isolation Firestore prod/staging.
#
# Interdit l'accès direct à la base Firestore hors des points de routage
# centralisés :
#   - Flutter  → `firestoreProvider` (lib/core/config/firestore_provider.dart)
#   - Functions → `dbForRequest` / `dbForLandlordUid` (functions/src/utils/db_router.ts)
#
# Sans ce garde-fou, un dev qui retape `FirebaseFirestore.instance(For)` ou
# `admin.firestore()` fait fuir l'isolation : une écriture staging atterrit en
# prod. Voir docs/adr/0003-firestore-prod-staging-isolation.md.
set -euo pipefail

# Toujours partir de la racine du repo (chemins lib/ + functions/ relatifs).
cd "$(git rev-parse --show-toplevel)"

fail=0

# --- Flutter : FirebaseFirestore.instance ET .instanceFor interdits hors
# provider + main.dart. Le préfixe `FirebaseFirestore\.instance` matche les DEUX
# (`.instance` et `.instanceFor`) — un dev pourrait sinon copier
# `instanceFor(app: ..., databaseId: '(default)')` en dur et contourner le
# provider. Le câblage émulateur de main.dart et les commentaires (///) sont
# exemptés.
flutter_bad=$(grep -rnE "FirebaseFirestore\.instance" lib/ \
  | grep -vE "lib/core/config/firestore_provider.dart|lib/main.dart" \
  | grep -vE ":[0-9]+:[[:space:]]*///" || true)
if [ -n "$flutter_bad" ]; then
  echo "❌ Accès Firestore direct interdit dans lib/ — passer par firestoreProvider :"
  echo "$flutter_bad"
  fail=1
fi

# --- Functions : admin.firestore() / getFirestore() interdits dans TOUT
# functions/src/ sauf le routeur lui-même (db_router.ts), les crons
# (scheduled/) et les triggers Firestore, qui restent sur (default)
# volontairement (pas de notion d'environnement pour eux). Scanner tout le
# dossier — et pas seulement callable/+http/ — ferme le contournement « helper
# déporté dans utils/ appelé depuis une callable ».
fn_bad=$(grep -rnE "admin\.firestore\(\)|getFirestore\(" functions/src/ 2>/dev/null \
  | grep -vE "functions/src/utils/db_router.ts|functions/src/scheduled/|functions/src/triggers/|functions/src/__tests__/" \
  || true)
if [ -n "$fn_bad" ]; then
  echo "❌ Accès Firestore direct interdit dans functions/src/ (hors db_router/scheduled/triggers) — router via db_router :"
  echo "$fn_bad"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "✅ Isolation Firestore (ADR 0003) respectée."
fi
exit "$fail"
