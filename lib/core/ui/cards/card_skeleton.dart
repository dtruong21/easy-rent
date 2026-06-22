import 'package:flutter/material.dart';

import '../theme/app_radii.dart';

/// Squelette de chargement reproduisant la forme d'un [EntityCard].
///
/// Affiche 3 lignes de placeholder sans animation shimmer (Phase 0).
/// Utilise `outlineVariant` à 60% d'opacité pour les barres de placeholder.
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radii = theme.extension<AppRadii>() ?? const AppRadii();

    final placeholderColor = colorScheme.outlineVariant.withAlpha(153);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radii.md),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ligne 1 : titre (80% de largeur)
          _SkeletonBar(color: placeholderColor, widthFactor: 0.8, height: 16),
          const SizedBox(height: 8),
          // Ligne 2 : sous-titre (60% de largeur)
          _SkeletonBar(color: placeholderColor, widthFactor: 0.6, height: 12),
          const SizedBox(height: 8),
          // Ligne 3 : info secondaire (40% de largeur)
          _SkeletonBar(color: placeholderColor, widthFactor: 0.4, height: 12),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.color,
    required this.widthFactor,
    required this.height,
  });

  final Color color;
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
