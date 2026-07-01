import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Stack sérif partagé — Cochin/Palatino avec fallback lisible (miroir de
/// `login_page.dart`).
const List<String> serifFallback = [
  'Palatino Linotype',
  'Book Antiqua',
  'Palatino',
  'Georgia',
  'serif',
];

/// Bloc éditorial de la landing : wordmark « Baillan. » + tagline.
///
/// Composant séparé de [LandingPage] pour rester < 200 lignes par fichier
/// (convention CLAUDE.md) et pour être réutilisable en test isolé.
class LandingHero extends StatelessWidget {
  const LandingHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Baillan.',
          style: TextStyle(
            fontFamily: 'Cochin',
            fontFamilyFallback: serifFallback,
            fontSize: 56,
            fontWeight: FontWeight.w500,
            color: AppTheme.ink,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Simulez votre prochain investissement locatif, ou gérez le '
          'registre de vos biens.',
          style: TextStyle(
            fontFamily: 'Cochin',
            fontFamilyFallback: serifFallback,
            fontStyle: FontStyle.italic,
            fontSize: 22,
            height: 1.4,
            color: AppTheme.inkMuted,
          ),
        ),
      ],
    );
  }
}
