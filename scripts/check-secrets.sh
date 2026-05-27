#!/usr/bin/env bash
# Détecte des patterns de secrets connus dans les fichiers stagés.
# Utilisé comme git pre-commit hook (voir scripts/install-hooks.sh).

set -e

# Liste des patterns suspects (regex étendues)
PATTERNS=(
  # Supabase secret keys (nouveau format)
  'sb_secret_[A-Za-z0-9_-]{20,}'
  # Supabase service role (ancien format JWT — commence souvent par eyJ et contient "service_role")
  'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
  # Resend API key
  're_[A-Za-z0-9]{20,}'
  # Stripe live keys
  'sk_live_[A-Za-z0-9]{20,}'
  'rk_live_[A-Za-z0-9]{20,}'
  # GitHub Personal Access Tokens
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  # Generic high-entropy patterns
  '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----'
  # AWS
  'AKIA[0-9A-Z]{16}'
  # Google API keys
  'AIza[0-9A-Za-z_-]{35}'
)

# Fichiers à scanner = fichiers stagés (mode commit) ou tout l'arborescence (mode manuel)
if [ "${1:-}" = "--all" ]; then
  echo "🔍 Scan complet du dépôt..."
  FILES=$(git ls-files)
else
  FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
fi

if [ -z "$FILES" ]; then
  exit 0
fi

# On ignore les binaires et les fichiers documentation qui peuvent contenir des exemples
FOUND=0
for file in $FILES; do
  # Skip binaires et patterns par extension
  if ! [ -f "$file" ]; then continue; fi
  case "$file" in
    *.png|*.jpg|*.jpeg|*.gif|*.ico|*.pdf|*.zip|*.tar|*.gz|*.lock) continue ;;
  esac

  # Skip les fichiers de doc qui peuvent légitimement mentionner les patterns
  case "$file" in
    docs/SECURITY.md|scripts/check-secrets.sh|scripts/install-hooks.sh|*.example.*|*.md.tmpl) continue ;;
  esac

  for pattern in "${PATTERNS[@]}"; do
    if grep -E -n "$pattern" "$file" > /dev/null 2>&1; then
      echo "🚨 SECRET DÉTECTÉ dans $file :"
      grep -E -n "$pattern" "$file" | head -3
      echo ""
      FOUND=1
    fi
  done
done

if [ "$FOUND" -eq 1 ]; then
  echo ""
  echo "❌ Commit BLOQUÉ — secrets détectés."
  echo "→ Supprime les valeurs sensibles, déplace-les vers dart-defines.json (gitignored)"
  echo "→ Si fausse alerte : retire le fichier du commit ou ajoute une exception dans scripts/check-secrets.sh"
  echo ""
  echo "Pour rotate immédiatement les clés exposées : voir docs/SECURITY.md"
  exit 1
fi

exit 0
