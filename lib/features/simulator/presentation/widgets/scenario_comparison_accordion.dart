import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/investment_scenario.dart';
import '../../domain/scenario_comparison_view_model.dart';
import 'scenario_comparison_cell.dart';

/// Vue accordéon mobile de la comparaison de scénarios (FEAT-055, < 720 px).
///
/// Un [ExpansionTile] par KPI, tous fermés par défaut (place à l'écran).
/// Le titre plié affiche déjà la valeur de la colonne de référence.
class ScenarioComparisonAccordion extends StatelessWidget {
  const ScenarioComparisonAccordion({
    super.key,
    required this.scenarios,
    required this.rows,
  });

  final List<InvestmentScenario> scenarios;
  final List<ComparisonRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (int i = 0; i < scenarios.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: i == 0
                        ? Border.all(color: theme.colorScheme.primary, width: 1)
                        : null,
                  ),
                  child: Text(
                    i == 0
                        ? '${scenarios[i].name} · ${l10n.simulatorCompareReferenceChip}'
                        : scenarios[i].name,
                    style: theme.textTheme.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        for (final row in rows)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: ExpansionTile(
              key: Key('compare_kpi_${row.kpi.name}'),
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                row.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  row.values[0].display,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < row.values.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            scenarios[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ScenarioComparisonCell(
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
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
