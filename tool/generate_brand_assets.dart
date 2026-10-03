// Générateur des masters PNG de marque Baillan (FEAT-024 — icônes + splash
// natifs). Rendu offscreen avec la VRAIE fonte EB Garamond du repo, pour une
// fidélité parfaite au favicon (B sérif italique + paraphe) et au BrandMark.
//
// Exécution (n'est PAS ramassé par `flutter test` qui ne couvre que test/) :
//   flutter test tool/generate_brand_assets.dart
//
// Produit dans assets/brand/ :
//   icon_full_1024.png        — plein-bleed encre (iOS + Android legacy + web)
//   icon_foreground_1024.png  — calque adaptive Android (fond transparent)
//   icon_monochrome_1024.png  — calque themed icons Android 13 (alpha only)
//   splash_logo_1024.png      — badge BrandMark transparent (splash natif)
//   android12_icon_1152.png   — icône splash Android 12+ (cercle central)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Palette AppTheme (lib/core/theme/app_theme.dart) — dupliquée sciemment :
// l'outil ne dépend pas de lib/ pour rester exécutable en toute circonstance.
const _ink = Color(0xFF1B1A17);
const _paper = Color(0xFFF7F4ED);
const _oliveSoft = Color(0xFFB5B89D);

Future<void> _loadBrandFont() async {
  final loader = FontLoader('EB Garamond')
    ..addFont(rootBundle.load('assets/fonts/EBGaramond-SemiBoldItalic.ttf'));
  await loader.load();
}

/// Dessine le monogramme « B » + paraphe, centré dans [rect].
/// [glyphScale] : hauteur de fonte relative au côté de [rect].
void _paintMonogram(
  Canvas canvas,
  Rect rect, {
  required Color glyphColor,
  required Color swashColor,
  double glyphScale = 0.62,
}) {
  final side = rect.width;
  final fontSize = side * glyphScale;

  final textPainter = TextPainter(
    text: TextSpan(
      text: 'B',
      style: TextStyle(
        fontFamily: 'EB Garamond',
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
        height: 1.0,
        color: glyphColor,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  // Écho du favicon (viewBox 100) : B posé au-dessus du paraphe
  // « M 22 84 Q 50 98 78 84 » — transposé dans rect.
  final swashY = rect.top + side * 0.84;
  final swashDip = rect.top + side * 0.975;
  final glyphCenterY = rect.top + side * 0.44;

  textPainter.paint(
    canvas,
    Offset(
      rect.left + (side - textPainter.width) / 2,
      glyphCenterY - textPainter.height / 2,
    ),
  );

  final swash = Path()
    ..moveTo(rect.left + side * 0.22, swashY)
    ..quadraticBezierTo(
      rect.left + side * 0.50,
      swashDip,
      rect.left + side * 0.78,
      swashY,
    );
  canvas.drawPath(
    swash,
    Paint()
      ..color = swashColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.028
      ..strokeCap = StrokeCap.round,
  );
}

Future<void> _savePng(ui.Image image, String path) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('écrit: $path (${file.lengthSync()} octets)');
}

Future<ui.Image> _render(
  double size,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  return recorder.endRecording().toImage(size.toInt(), size.toInt());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadBrandFont);

  test('génère les masters de marque dans assets/brand/', () async {
    const s = 1024.0;
    const rect = Rect.fromLTWH(0, 0, s, s);

    // 1. Icône plein-bleed : fond encre, monogramme légèrement réduit pour
    //    survivre aux masques (cercle iOS/Android ≈ 80 % du carré).
    final full = await _render(s, (c) {
      c.drawRect(rect, Paint()..color = _ink);
      _paintMonogram(
        c,
        Rect.fromCenter(center: rect.center, width: s * 0.78, height: s * 0.78),
        glyphColor: _paper,
        swashColor: _oliveSoft,
      );
    });
    await _savePng(full, 'assets/brand/icon_full_1024.png');

    // 2. Calque adaptive Android : transparent, contenu dans la safe zone
    //    (66 % centraux) avec marge de respiration.
    final foreground = await _render(s, (c) {
      _paintMonogram(
        c,
        Rect.fromCenter(center: rect.center, width: s * 0.46, height: s * 0.46),
        glyphColor: _paper,
        swashColor: _oliveSoft,
      );
    });
    await _savePng(foreground, 'assets/brand/icon_foreground_1024.png');

    // 3. Calque monochrome (themed icons Android 13) : seul l'alpha compte —
    //    tout en blanc opaque pour un masque net.
    final monochrome = await _render(s, (c) {
      _paintMonogram(
        c,
        Rect.fromCenter(center: rect.center, width: s * 0.46, height: s * 0.46),
        glyphColor: Colors.white,
        swashColor: Colors.white,
      );
    });
    await _savePng(monochrome, 'assets/brand/icon_monochrome_1024.png');

    // 4. Logo splash : badge BrandMark (carré arrondi 22 %, écho AppBar) sur
    //    fond transparent — lisible sur paper (light) comme sur ink (dark).
    final splash = await _render(s, (c) {
      final badge = Rect.fromCenter(
        center: rect.center,
        width: s * 0.5,
        height: s * 0.5,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(badge, Radius.circular(badge.width * 0.22)),
        Paint()..color = _ink,
      );
      _paintMonogram(
        c,
        badge.deflate(badge.width * 0.08),
        glyphColor: _paper,
        swashColor: _oliveSoft,
      );
    });
    await _savePng(splash, 'assets/brand/splash_logo_1024.png');

    // 5. Android 12+ : canvas 1152, contenu dans le cercle central de 768.
    const s12 = 1152.0;
    final android12 = await _render(s12, (c) {
      final badge = Rect.fromCenter(
        center: const Offset(s12 / 2, s12 / 2),
        width: 500,
        height: 500,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(badge, Radius.circular(badge.width * 0.22)),
        Paint()..color = _ink,
      );
      _paintMonogram(
        c,
        badge.deflate(badge.width * 0.08),
        glyphColor: _paper,
        swashColor: _oliveSoft,
      );
    });
    await _savePng(android12, 'assets/brand/android12_icon_1152.png');
  });
}
