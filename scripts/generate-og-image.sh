#!/usr/bin/env bash
# Génère la carte sociale Open Graph de Baillan (1200x630) :
#   - web/icons/og-image-1200x630.png        (app Flutter)
#   - site/public/icons/og-image-1200x630.png (vitrine Astro, balises og:image/twitter:image)
# Les deux fichiers sont identiques ; les régénérer ensemble par ce script.
#
# Source éditable : scripts/og-image.svg (charte encre/papier/accent, « B »
# paraphe en Cochin italique — cf. le favicon inline de web/index.html).
# Rendu SVG -> PNG via rsvg-convert (librsvg). PNG voulu (PAS webp) : certains
# scrapers sociaux (LinkedIn, iMessage, WhatsApp) ne lisent pas le webp.
#
# Prérequis :
#   brew install librsvg   # fournit rsvg-convert
#   Police Cochin : présente d'origine sur macOS. Ailleurs, repli automatique
#   Palatino > Georgia > serif (déclaré dans le SVG) — l'esprit reste serif.
#
# Pour modifier la carte : éditer scripts/og-image.svg puis relancer ce script.
# Vérifs post-génération : dimensions 1200x630 (ratio 1.91:1), aperçu dans le
# LinkedIn Post Inspector + le Sharing Debugger Facebook (voir docs/SEO.md §6).

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/og-image.svg"
OUTS=(
  "$DIR/../web/icons/og-image-1200x630.png"
  "$DIR/../site/public/icons/og-image-1200x630.png"
)

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "Erreur : rsvg-convert introuvable. Installer avec : brew install librsvg" >&2
  exit 1
fi

for OUT in "${OUTS[@]}"; do
  mkdir -p "$(dirname "$OUT")"
  rsvg-convert -w 1200 -h 630 "$SRC" -o "$OUT"
  echo "  ✓ $(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")  (1200x630)"
done
