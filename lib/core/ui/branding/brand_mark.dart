import 'package:flutter/material.dart';

/// Marque Baillan : carré arrondi (encre / `onSurface`) + « B » sérif crème
/// (`surface`) — écho typographique du favicon, aucun asset image. S'inverse
/// proprement en dark mode (carré clair, « B » encre).
///
/// Partagée entre le rail de navigation (desktop) et l'AppBar (mobile) pour
/// maximiser la présence de marque sur toutes les tailles d'écran.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.onSurface,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      alignment: Alignment.center,
      child: Text(
        'B',
        style: TextStyle(
          fontFamily: 'EB Garamond',
          fontFamilyFallback: const ['Georgia', 'serif'],
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          fontSize: size * 0.62,
          height: 1.0,
          color: colorScheme.surface,
        ),
      ),
    );
  }
}
