import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/investment_scenario.dart';
import '../../domain/scenario_comparison_view_model.dart';
import 'scenario_comparison_cell.dart';

/// Vue tableau de la comparaison de scénarios (FEAT-055, largeur suffisante
/// — cf. [fitsWidth]).
///
/// Une colonne par scénario ; la première est la « référence ». Six lignes,
/// une par KPI. Cellules déléguées à [ScenarioComparisonCell] pour préserver
/// un format cohérent (valeur + delta % coloré). Colonnes de scénario
/// **fluides** (`FlexColumnWidth`, à parts égales) : le tableau tient
/// toujours dans la largeur disponible, jamais de scroll horizontal
/// (responsive rework 2026-07-26).
class ScenarioComparisonTable extends StatelessWidget {
  const ScenarioComparisonTable({
    super.key,
    required this.scenarios,
    required this.rows,
  });

  final List<InvestmentScenario> scenarios;
  final List<ComparisonRow> rows;

  /// Largeur minimale jugée lisible pour une colonne de scénario (nom +
  /// valeur + delta % sans compression excessive du texte).
  static const double minColumnWidth = 168.0;

  /// Estimation de la largeur de la colonne libellés (le KPI le plus long
  /// en V1 est « Coût total crédit »). Sert uniquement à la décision
  /// table vs cartes ([fitsWidth]) — le rendu réel mesure la vraie largeur
  /// via `IntrinsicColumnWidth`.
  static const double _labelColumnWidthEstimate = 140.0;

  /// `true` si [availableWidth] (largeur de la zone de contenu, hors
  /// paddings) permet d'afficher [scenarioCount] colonnes fluides sans les
  /// compresser sous [minColumnWidth].
  ///
  /// Dépend du nombre de scénarios comparés (2 ou 3, cf.
  /// `SavedScenariosRow._maxSelection`) plutôt que d'une constante de
  /// largeur fixe : 2 scénarios tiennent dans une fenêtre où 3 ne
  /// tiendraient pas.
  static bool fitsWidth(double availableWidth, int scenarioCount) {
    final required = _labelColumnWidthEstimate + scenarioCount * minColumnWidth;
    return availableWidth >= required;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      columnWidths: {
        0: const IntrinsicColumnWidth(),
        for (int i = 1; i <= scenarios.length; i++) i: const FlexColumnWidth(),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            for (int i = 0; i < scenarios.length; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      scenarios[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (i == 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          l10n.simulatorCompareReferenceChip,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 24, 14),
                child: Text(
                  row.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (int i = 0; i < row.values.length; i++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  child: ScenarioComparisonCell(
                    value: row.values[i],
                    deltaPercent: i == 0
                        ? null
                        : computeSignedDeltaPercent(
                            row.values[0].rawNumber,
                            row.values[i].rawNumber,
                          ),
                    higherIsBetter: row.kpi.higherIsBetter,
                    isReference: i == 0,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
