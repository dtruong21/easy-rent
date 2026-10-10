import 'package:flutter/material.dart';

import '../../../../core/ui/theme/app_colors.dart';
import '../../domain/scenario_comparison_view_model.dart';

/// Cellule atomique de la comparaison de scénarios (FEAT-055).
///
/// Rend la valeur formatée + éventuel delta % signé, coloré selon le sens
/// favorable du KPI et le seuil ± 5 % (décision par défaut D5 du plan).
/// Couleurs pilotées par le thème Baillan (aucune couleur en dur) : le delta
/// favorable reprend `AppColors.success.solid` — même token que le KPI
/// « loyers » du dashboard pour une sémantique identique (valeur au-dessus
/// vs en-dessous d'une référence) — le delta défavorable reprend
/// `colorScheme.error`, déjà utilisé ici. Les deux sont déclinés light/dark.
class ScenarioComparisonCell extends StatelessWidget {
  const ScenarioComparisonCell({
    super.key,
    required this.value,
    required this.deltaPercent,
    required this.higherIsBetter,
    this.isReference = false,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final ComparisonValue value;

  /// `null` sur la colonne de référence (aucun delta n'est calculé) ou
  /// quand la référence est zéro (division impossible).
  final double? deltaPercent;

  /// Sens économique : `true` = un scénario meilleur donne une valeur plus
  /// haute (rendements, cash-flow) ; `false` = plus bas (coût crédit,
  /// apport, effort d'épargne).
  final bool higherIsBetter;

  final bool isReference;

  /// Alignement horizontal du bloc valeur/delta. `start` (défaut, table
  /// desktop) ou `end` (cartes mobile [ScenarioComparisonCards], montants
  /// alignés à droite en bout de ligne).
  final CrossAxisAlignment crossAxisAlignment;

  static const double _signalThreshold = 5.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value.display,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (deltaPercent != null && !isReference)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _formatDelta(deltaPercent!),
              style: theme.textTheme.labelSmall?.copyWith(
                color: _deltaColor(context, deltaPercent!),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Color _deltaColor(BuildContext context, double delta) {
    final theme = Theme.of(context);
    if (delta.abs() < _signalThreshold) {
      return theme.colorScheme.onSurfaceVariant;
    }
    final isFavorable = higherIsBetter ? delta > 0 : delta < 0;
    if (isFavorable) {
      return theme.extension<AppColors>()!.success.solid;
    }
    return theme.colorScheme.error;
  }

  String _formatDelta(double delta) {
    final rounded = delta.toStringAsFixed(1).replaceAll('.', ',');
    if (delta > 0) return '+$rounded %';
    if (delta < 0) return '−${rounded.substring(1)} %';
    return '0,0 %';
  }
}
