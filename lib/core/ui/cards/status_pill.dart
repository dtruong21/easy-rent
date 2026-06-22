import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'status_pill_tone.dart';

/// Pill de statut sémantique réutilisable.
///
/// Exemple d'utilisation :
/// ```dart
/// StatusPill(
///   label: 'Actif',
///   tone: StatusPillTone.success,
///   icon: Icons.check_circle_outline,
/// )
/// ```
///
/// Les couleurs sont résolues via [AppColors] du thème courant.
/// Veillez à ce que le thème inclue l'extension [AppColors].
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.variant = StatusPillVariant.subtle,
    this.size = StatusPillSize.md,
  });

  /// Texte affiché dans la pill.
  final String label;

  /// Tone sémantique (success, warning, danger, info, neutral).
  final StatusPillTone tone;

  /// Icône optionnelle affichée à gauche du label.
  final IconData? icon;

  /// Variante visuelle (subtle, filled, outlined).
  final StatusPillVariant variant;

  /// Taille de la pill (sm, md).
  final StatusPillSize size;

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>();
    assert(
      appColors != null,
      'AppColors ThemeExtension manquant — ajoutez-le dans ThemeData.extensions',
    );

    final colorSet = (appColors ?? AppColors.light).statusFor(tone);

    final double height = switch (size) {
      StatusPillSize.sm => 20,
      StatusPillSize.md => 24,
    };

    final double horizontalPadding = switch (size) {
      StatusPillSize.sm => 6,
      StatusPillSize.md => 8,
    };

    final double iconSize = switch (size) {
      StatusPillSize.sm => 12,
      StatusPillSize.md => 14,
    };

    final double fontSize = switch (size) {
      StatusPillSize.sm => 11,
      StatusPillSize.md => 12,
    };

    final Color bgColor = switch (variant) {
      StatusPillVariant.subtle => colorSet.surface,
      StatusPillVariant.filled => colorSet.solid,
      StatusPillVariant.outlined => Colors.transparent,
    };

    final Color fgColor = switch (variant) {
      StatusPillVariant.subtle => colorSet.onSurface,
      StatusPillVariant.filled => colorSet.onSolid,
      StatusPillVariant.outlined => colorSet.solid,
    };

    final Border? border = switch (variant) {
      StatusPillVariant.outlined => Border.all(color: colorSet.solid),
      _ => null,
    };

    return Semantics(
      label: '${tone.name}: $label',
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(height / 2),
          border: border,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: iconSize, color: fgColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: fgColor,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
