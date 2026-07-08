#!/usr/bin/env python3
"""Génère les masters d'icône d'app Baillan depuis la définition de marque.

Marque Baillan (identique au favicon SVG inline de web/index.html) :
  - fond encre  #1B1A17
  - « B » sérif italique crème #F7F4ED (police EB Garamond Italic, bundlée)
  - paraphe (léger sourire) sous le B, filet sauge #B5B89D

Sorties (assets/icon/) — consommées par flutter_launcher_icons :
  - baillan_icon_master.png      1024×1024, plein cadre, OPAQUE (pas d'alpha)
        → iOS marketing 1024 (App Store exige opaque) + Android legacy
  - baillan_icon_foreground.png  1024×1024, fond transparent, marque dans la
        safe zone centrale (~66%) → adaptive_icon_foreground Android 26+
        (le fond adaptatif est la couleur #1B1A17, cf. config)

Reproductible : `python3 tool/branding/generate_app_icons.py`
Dépendances : Pillow (>=10). Police lue directement depuis assets/fonts/.
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFont

# --- Racine du projet (ce script vit dans tool/branding/) ---
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT_PATH = os.path.join(ROOT, "assets", "fonts", "EBGaramond-Italic.ttf")
OUT_DIR = os.path.join(ROOT, "assets", "icon")

# --- Couleurs de marque ---
INK = (0x1B, 0x1A, 0x17, 0xFF)      # fond encre
CREAM = (0xF7, 0xF4, 0xED, 0xFF)    # B crème
SAGE = (0xB5, 0xB8, 0x9D, 0xFF)     # paraphe sauge

SIZE = 1024                          # master haute résolution
SS = 4                               # supersampling anti-aliasing


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


def _draw_mark(canvas_size, *, transparent, content_scale):
    """Rend la marque (B + paraphe) centrée.

    content_scale : fraction de la largeur de canevas occupée par la marque
        (1.0 = plein cadre master ; ~0.62 = safe zone adaptative Android).
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
    draw.text((bx, by), "B", font=font, fill=CREAM)

    # Paraphe centré sous le B
    sw_y = top + bh + gap
    x0 = cx - swoosh_w / 2.0
    x2 = cx + swoosh_w / 2.0
    pts = _quad_bezier((x0, sw_y), (cx, sw_y + dip * 2), (x2, sw_y))
    _draw_stroke(draw, pts, SAGE, stroke)

    return img.resize((canvas_size, canvas_size), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # Master plein cadre, opaque (iOS 1024 + Android legacy)
    master = _draw_mark(SIZE, transparent=False, content_scale=0.86)
    master_rgb = Image.new("RGB", (SIZE, SIZE), INK[:3])
    master_rgb.paste(master, (0, 0), master)
    master_rgb.save(os.path.join(OUT_DIR, "baillan_icon_master.png"))

    # Foreground adaptatif : la marque remplit presque tout le cadre. La safe
    # zone est fournie par l'inset 16% du template adaptive-icon de
    # flutter_launcher_icons (foreground effectif ~0.68 du canvas), ce qui place
    # le contenu (~0.90 ici) autour de 0.61 du canevas final = safe zone Android.
    fg = _draw_mark(SIZE, transparent=True, content_scale=0.90)
    fg.save(os.path.join(OUT_DIR, "baillan_icon_foreground.png"))

    print("OK ->", OUT_DIR)


if __name__ == "__main__":
    main()
