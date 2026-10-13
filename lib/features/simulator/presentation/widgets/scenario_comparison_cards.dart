import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/investment_scenario.dart';
import '../../domain/scenario_comparison_view_model.dart';
import 'scenario_comparison_cell.dart';

/// Vue « une carte par KPI » de la comparaison de scénarios (FEAT-055,
/// largeur insuffisante pour la table — cf. `ScenarioComparisonTable.fitsWidth`).
///
/// Une [Card] par KPI, **toutes les lignes visibles d'emblée** (aucun
/// dépliage) : nom du scénario à gauche (tronqué), valeur + delta % à droite.
/// Remplace l'ancien accordéon replié par défaut, qui cachait justement ce
/// qu'on venait comparer (responsive rework 2026-07-26).
class ScenarioComparisonCards extends StatelessWidget {
  const ScenarioComparisonCards({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
          _KpiCard(
            key: Key('compare_kpi_${row.kpi.name}'),
            row: row,
            scenarios: scenarios,
          ),
      ],
    );
  }
}

/// Une carte = un KPI, une ligne par scénario (toutes visibles).
class _KpiCard extends StatelessWidget {
  const _KpiCard({super.key, required this.row, required this.scenarios});

  final ComparisonRow row;
  final List<InvestmentScenario> scenarios;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              row.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            for (int i = 0; i < row.values.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      // La chip « Référence » dédiée vit dans la rangée
                      // d'en-tête (une fois pour toute la comparaison, cf.
                      // pattern déjà utilisé par la table desktop) — ici, un
                      // simple accent de poids typographique suffit à
                      // identifier la ligne de référence sans jamais risquer
                      // de déborder sur les petits écrans (2-3 scénarios ×
                      // valeur + delta déjà larges).
                      child: Text(
                        scenarios[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: i == 0
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
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
                      crossAxisAlignment: CrossAxisAlignment.end,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
