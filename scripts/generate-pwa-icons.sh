#!/usr/bin/env bash
# Génère les icônes PWA placeholder "ER" sur fond teal #0F766E.
# Nécessite ImageMagick (convert). Installation : brew install imagemagick

set -euo pipefail

ICONS_DIR="$(dirname "$0")/../web/icons"
mkdir -p "$ICONS_DIR"

echo "Génération des icônes PWA (ImageMagick)..."

# 192x192 — icône standard
convert \
  -size 192x192 xc:'#0F766E' \
  -fill white \
  -gravity Center \
  -font Helvetica-Bold \
  -pointsize 80 \
  -annotate +0+0 'ER' \
  "$ICONS_DIR/Icon-192.png"

echo "  ✓ Icon-192.png"

# 512x512 — icône grande
convert \
  -size 512x512 xc:'#0F766E' \
  -fill white \
  -gravity Center \
  -font Helvetica-Bold \
  -pointsize 210 \
  -annotate +0+0 'ER' \
  "$ICONS_DIR/Icon-512.png"

echo "  ✓ Icon-512.png"

# 192x192 — maskable (plein bord, safe zone 80%)
convert \
  -size 192x192 xc:'#0F766E' \
  -fill white \
  -gravity Center \
  -font Helvetica-Bold \
  -pointsize 64 \
  -annotate +0+0 'ER' \
  "$ICONS_DIR/Icon-maskable-192.png"

echo "  ✓ Icon-maskable-192.png"

# 512x512 — maskable
convert \
  -size 512x512 xc:'#0F766E' \
  -fill white \
  -gravity Center \
  -font Helvetica-Bold \
  -pointsize 170 \
  -annotate +0+0 'ER' \
  "$ICONS_DIR/Icon-maskable-512.png"

echo "  ✓ Icon-maskable-512.png"

echo "Icônes générées dans $ICONS_DIR"
