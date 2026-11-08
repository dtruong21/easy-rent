#!/usr/bin/env bash
# Détecte des patterns de secrets connus dans les fichiers stagés.
# Utilisé comme git pre-commit hook (voir scripts/install-hooks.sh).

set -e

# Liste des patterns suspects (regex étendues)
PATTERNS=(
  # JWT (3 segments base64url) — attrape tout token type service account / session
  'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
  # Resend API key
  're_[A-Za-z0-9]{20,}'
  # Stripe — préfixes vérifiés sur docs.stripe.com/keys (2026-10-05) : clés
  # secrètes et limitées live ET test, clés d'organisation, secrets de
  # signature de webhook (docs.stripe.com/webhooks/signature : « whsec_ »).
  # Une clé de test en clair reste une fuite (et signe souvent une confusion
  # d'environnement, cf. #138).
  'sk_live_[A-Za-z0-9]{20,}'
  'rk_live_[A-Za-z0-9]{20,}'
  'sk_test_[A-Za-z0-9]{20,}'
  'rk_test_[A-Za-z0-9]{20,}'
  'sk_org_[A-Za-z0-9]{20,}'
  'whsec_[A-Za-z0-9]{20,}'
  # RevenueCat — clé SECRÈTE (REVENUECAT_API_KEY) : préfixe « sk_ » documenté
  # (revenuecat.com/docs/projects/authentication), longueur non documentée →
  # plancher de 20 caractères comme pour Stripe. Ancré sur un début de mot :
  # sans ça, « task_… » ou « mask_… » déclencheraient. Les clés Stripe
  # (sk_live_/sk_test_/sk_org_) ne matchent pas ce motif (« _ » après le mode).
  # NON détectable : REVENUECAT_WEBHOOK_AUTH — valeur LIBRE choisie dans le
  # dashboard RevenueCat (pas de format) ; seule la discipline la protège.
  # Les clés PUBLIQUES du SDK (appl_, goog_…) ne sont pas des secrets.
  '(^|[^A-Za-z0-9_])sk_[A-Za-z0-9]{20,}'
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

  # Skip ce script et l'installeur du hook (ils contiennent les motifs eux-mêmes)
  # + configs Firebase clientes : les apiKey Firebase (AIza…) y sont PUBLIQUES
  #   par design (comme toute clé client Firebase) ; sécurité via Rules +
  #   App Check. Couvre le web (firebase_options.dart) et les apps natives
  #   FEAT-024 (google-services.json Android, GoogleService-Info.plist iOS).
  case "$file" in
    # docs/SECURITY.md n'est PLUS exclu (#131) : il ne cite les motifs que sous
    # forme abrégée (« sk_live_… ») et ne déclenche aucun d'eux — l'exclure
    # rendait invisible une vraie clé collée dans ce fichier.
    scripts/check-secrets.sh|scripts/install-hooks.sh|*.example.*|*.md.tmpl) continue ;;
    lib/firebase_options.dart) continue ;;
    android/app/google-services.json|ios/Runner/GoogleService-Info.plist) continue ;;
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
