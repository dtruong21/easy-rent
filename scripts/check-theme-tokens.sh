#!/usr/bin/env bash
# Garde-fou — miroirs de la palette à jour.
#
# Échoue si `app_palette.g.dart` ou `tokens.css` diffèrent de ce que produit
# le générateur. Deux causes possibles : un miroir édité à la main, ou la
# source canonique modifiée sans régénérer. Dans les deux cas, la vitrine et
# l'app risquent d'afficher des couleurs différentes.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

dart_out="lib/core/theme/app_palette.g.dart"
css_out="site/src/styles/tokens.css"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Sauvegarder l'état commité pour le comparer au résultat régénéré. On compare
# aux fichiers de l'ARBRE DE TRAVAIL, pas à `git diff` : un miroir encore non
# suivi par git échapperait sinon à la vérification.
for f in "$dart_out" "$css_out"; do
  if [ ! -f "$f" ]; then
    echo "❌ Miroir manquant : $f — lancer : dart run tool/gen_theme_tokens.dart"
    exit 1
  fi
  cp "$f" "$tmp/$(basename "$f").before"
done

dart run tool/gen_theme_tokens.dart >/dev/null
dart format "$dart_out" >/dev/null

fail=0
for f in "$dart_out" "$css_out"; do
  if ! diff -q "$tmp/$(basename "$f").before" "$f" >/dev/null; then
    echo "❌ $f est périmé :"
    diff -u "$tmp/$(basename "$f").before" "$f" | head -30 || true
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "   Régénérer puis committer : dart run tool/gen_theme_tokens.dart"
  exit 1
fi

echo "✅ Miroirs de la palette à jour."
