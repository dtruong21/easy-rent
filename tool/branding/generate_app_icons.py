#!/usr/bin/env python3
"""Génère les assets de marque Baillan (icônes d'app + splash) depuis la marque.

Marque Baillan (identique au favicon SVG inline de web/index.html) :
  - fond encre  #1B1A17
  - « B » sérif italique (police EB Garamond Italic, bundlée)
  - paraphe (léger sourire) sous le B

Sorties :

assets/icon/ — consommées par flutter_launcher_icons :
  - baillan_icon_master.png      1024×1024, plein cadre, OPAQUE (pas d'alpha)
        → iOS marketing 1024 (App Store exige opaque) + Android legacy
  - baillan_icon_foreground.png  1024×1024, fond transparent, marque dans la
        safe zone (~0.90 ici, ramenée en safe zone par l'inset 16% du template)

assets/splash/ — consommées par flutter_native_splash (fond transparent) :
  - baillan_glyph_ink.png    1152×1152, « B » encre #1B1A17 + paraphe olive
        #3F4A2A → splash mode CLAIR (sur fond papier #F7F4ED)
  - baillan_glyph_cream.png  1152×1152, « B » crème #F7F4ED + paraphe sauge
        #B5B89D → splash mode SOMBRE (sur fond encre #1B1A17, = tuile d'icône)
  La marque tient dans le cercle safe de 768 px (Android 12 masque en cercle le
  splash icon sur un canevas 1152 sans icon_background_color).

Reproductible : `python3 tool/branding/generate_app_icons.py`
Dépendances : Pillow (>=10). Police lue directement depuis assets/fonts/.
"""

from __future__ import annotations

import math
import os
from PIL import Image, ImageDraw, ImageFont

# --- Racine du projet (ce script vit dans tool/branding/) ---
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT_PATH = os.path.join(ROOT, "assets", "fonts", "EBGaramond-Italic.ttf")
ICON_DIR = os.path.join(ROOT, "assets", "icon")
SPLASH_DIR = os.path.join(ROOT, "assets", "splash")

# --- Couleurs de marque (cf. lib/core/theme/app_theme.dart) ---
INK = (0x1B, 0x1A, 0x17, 0xFF)      # encre : fond icône, scaffold sombre
CREAM = (0xF7, 0xF4, 0xED, 0xFF)    # papier/crème : B sur fond sombre
SAGE = (0xB5, 0xB8, 0x9D, 0xFF)     # sauge (oliveSoft) : paraphe, accent sombre
OLIVE = (0x3F, 0x4A, 0x2A, 0xFF)    # olive : primaire clair (paraphe sur papier)

SS = 4                               # supersampling anti-aliasing
# Android 12 splash (sans icon_background_color) : canevas 1152, cercle safe 768.
A12_SIZE = 1152
A12_SAFE_D = 768


def _quad_bezier(p0, p1, p2, steps=240):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0]
        y = u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]
        pts.append((x, y))
    return pts


def _draw_stroke(draw, pts, color, width):
    """Trace une polyligne épaisse avec bouts ronds (approx stroke-linecap)."""
    draw.line(pts, fill=color, width=width, joint="curve")
    r = width // 2
    for x, y in (pts[0], pts[-1]):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=color)


def _draw_mark(canvas_size, *, transparent, content_scale,
               b_color=CREAM, swoosh_color=SAGE):
    """Rend la marque (B + paraphe) centrée.

    content_scale : fraction de la largeur de canevas occupée par la marque.
    b_color / swoosh_color : permettent les variantes claire/sombre.
    """
    S = canvas_size * SS
    bg = (0, 0, 0, 0) if transparent else INK
    img = Image.new("RGBA", (S, S), bg)
    draw = ImageDraw.Draw(img)

    # --- Le « B » : on cherche la taille de police qui donne la largeur cible ---
    target_w = S * content_scale * 0.60   # le B occupe ~60% de la zone de marque
    font_px = int(S * 0.62)
    font = ImageFont.truetype(FONT_PATH, font_px)
    bbox = draw.textbbox((0, 0), "B", font=font)
    bw = bbox[2] - bbox[0]
    font_px = max(1, int(font_px * target_w / bw))
    font = ImageFont.truetype(FONT_PATH, font_px)
    bbox = draw.textbbox((0, 0), "B", font=font)
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]

    # --- Géométrie du paraphe : sourire sous le B ---
    swoosh_w = bw * 1.16
    gap = S * 0.045 * content_scale
    dip = S * 0.028 * content_scale
    stroke = max(2, int(S * 0.016 * content_scale))

    group_h = bh + gap + dip
    top = (S - group_h) / 2.0
    cx = S / 2.0

    # B centré horizontalement, calé sur `top` (on retire l'offset de bbox)
    bx = cx - bw / 2.0 - bbox[0]
    by = top - bbox[1]
    draw.text((bx, by), "B", font=font, fill=b_color)

    # Paraphe centré sous le B
    sw_y = top + bh + gap
    x0 = cx - swoosh_w / 2.0
    x2 = cx + swoosh_w / 2.0
    pts = _quad_bezier((x0, sw_y), (cx, sw_y + dip * 2), (x2, sw_y))
    _draw_stroke(draw, pts, swoosh_color, stroke)

    return img.resize((canvas_size, canvas_size), Image.LANCZOS)


def _max_ink_radius(img):
    """Rayon max (px) d'un pixel opaque depuis le centre — contrôle safe zone."""
    a = img.split()[3].load()
    W, H = img.size
    c = W / 2.0
    m = 0.0
    for y in range(H):
        for x in range(W):
            if a[x, y] > 40:
                r = math.hypot(x - c, y - c)
                if r > m:
                    m = r
    return m


def main():
    os.makedirs(ICON_DIR, exist_ok=True)
    os.makedirs(SPLASH_DIR, exist_ok=True)

    # === Icônes d'app (flutter_launcher_icons) ===
    master = _draw_mark(1024, transparent=False, content_scale=0.86)
    master_rgb = Image.new("RGB", (1024, 1024), INK[:3])
    master_rgb.paste(master, (0, 0), master)
    master_rgb.save(os.path.join(ICON_DIR, "baillan_icon_master.png"))

    fg = _draw_mark(1024, transparent=True, content_scale=0.90)
    fg.save(os.path.join(ICON_DIR, "baillan_icon_foreground.png"))

    # === Glyphes splash (flutter_native_splash) ===
    # content_scale 0.60 → marque bien à l'intérieur du cercle safe 768 px.
    ink_glyph = _draw_mark(A12_SIZE, transparent=True, content_scale=0.60,
                           b_color=INK, swoosh_color=OLIVE)
    cream_glyph = _draw_mark(A12_SIZE, transparent=True, content_scale=0.60,
                             b_color=CREAM, swoosh_color=SAGE)
    ink_glyph.save(os.path.join(SPLASH_DIR, "baillan_glyph_ink.png"))
    cream_glyph.save(os.path.join(SPLASH_DIR, "baillan_glyph_cream.png"))

    # Garde-fou : la marque DOIT tenir dans le cercle safe Android 12 (768 px),
    # sinon le masque circulaire du SplashScreen rognerait le tracé. On échoue
    # dur pour qu'une régénération future ne puisse pas livrer un glyphe débordant.
    safe_r = A12_SAFE_D / 2.0
    overflow = []
    for name, g in (("ink", ink_glyph), ("cream", cream_glyph)):
        r = _max_ink_radius(g)
        ok = r <= safe_r
        print(f"  splash {name}: rayon max {r:.0f}px / safe {safe_r:.0f}px  "
              f"{'OK' if ok else '!! DÉBORDE'}")
        if not ok:
            overflow.append(name)
    if overflow:
        raise SystemExit(
            f"Glyphe(s) splash hors cercle safe {A12_SAFE_D}px : {overflow}. "
            "Réduire content_scale dans main().")

    print("OK -> icônes:", ICON_DIR, "| splash:", SPLASH_DIR)


if __name__ == "__main__":
    main()
