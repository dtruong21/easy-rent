#!/usr/bin/env bash
# Vérifie que les schémas Postgres attendus (public + dev) sont exposés
# par l'API PostgREST du projet Supabase.
#
# Pourquoi ce check : sur Supabase Cloud, seul `public` est exposé par défaut.
# La stratégie multi-env d'EasyRent (cf. docs/ENVIRONMENTS.md) exige que `dev`
# le soit aussi, sinon TOUTES les requêtes staging échouent avec PGRST106
# "Invalid schema: dev". Cette config se règle dans le dashboard Supabase
# (Settings → API → Exposed schemas).
#
# Usage : ./scripts/check-supabase-schemas.sh [path/to/dart-defines.json]

set -e

CONFIG_FILE="${1:-dart-defines.json}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Fichier $CONFIG_FILE introuvable. Usage : $0 [path/to/dart-defines.json]"
  exit 1
fi

# Extraction simple via grep+sed pour éviter dépendance jq.
SUPABASE_URL=$(grep '"SUPABASE_URL"' "$CONFIG_FILE" | sed 's/.*"\(https:[^"]*\)".*/\1/')
SUPABASE_ANON_KEY=$(grep '"SUPABASE_ANON_KEY"' "$CONFIG_FILE" | sed 's/.*: *"\([^"]*\)".*/\1/')

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "❌ SUPABASE_URL ou SUPABASE_ANON_KEY introuvable dans $CONFIG_FILE"
  exit 1
fi

echo "🔍 Vérification des schémas exposés sur $SUPABASE_URL..."
echo

check_schema() {
  local schema="$1"
  local body_file code
  body_file=$(mktemp)
  code=$(curl -s -o "$body_file" -w "%{http_code}" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Accept-Profile: $schema" \
    "$SUPABASE_URL/rest/v1/landlords?select=id&limit=1")
  local body
  body=$(cat "$body_file")
  rm -f "$body_file"

  # 200 : schéma exposé + anon a GRANT (cas typique du schéma public)
  # 401 + code 42501 : schéma exposé mais anon n'a pas GRANT (cas voulu pour dev
  #                    — seul `authenticated` a accès, défini dans la migration init).
  #                    L'app marche en logged-in. C'est OK.
  # 406 + code PGRST106 : schéma PAS exposé dans l'API → FIX requis (dashboard).
  if [ "$code" = "200" ]; then
    echo "  ✅ $schema schema exposé (anon GRANT OK)"
    return 0
  elif [ "$code" = "401" ] && echo "$body" | grep -q "42501"; then
    echo "  ✅ $schema schema exposé (anon bloqué par GRANT — normal, only authenticated has access)"
    return 0
  elif [ "$code" = "406" ] && echo "$body" | grep -q "PGRST106"; then
    echo "  ❌ $schema schema NON exposé dans l'API (PGRST106 'Invalid schema')"
    return 1
  else
    echo "  ⚠️  $schema schema retour inattendu (HTTP $code) — body: $(echo "$body" | head -c 200)"
    return 1
  fi
}

failed=0
check_schema "public" || failed=1
check_schema "dev" || failed=1

echo
if [ "$failed" -eq 0 ]; then
  echo "✅ Setup Supabase OK — les 2 schémas sont exposés."
  exit 0
else
  echo "❌ Setup incomplet."
  echo
  echo "Fix : Supabase Dashboard → Project Settings → API → Data API → Exposed schemas"
  echo "→ Ajoute les schémas manquants à la liste séparée par virgules."
  echo "→ Save. Effet immédiat, pas besoin de redéployer."
  exit 1
fi
