import 'package:flutter/material.dart';

import '../../../../core/utils/money_format.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../domain/scenario_results.dart';

/// Grille 2 colonnes des 8 KPI du simulateur d'investissement.
///
/// Affiche les résultats calculés par [computeScenarioResults].
/// Inclut un disclaimer "avant impôt" sous le cash-flow.
class ScenarioResultsCard extends StatelessWidget {
  const ScenarioResultsCard({super.key, required this.results});

  final ScenarioResults results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Résultats estimés',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing.md),
            _KpiGrid(results: results),
            SizedBox(height: spacing.sm),
            _DisclaimerTile(
              icon: Icons.info_outline,
              text:
                  'Cash-flow affiché avant impôt — ne tient pas compte du '
                  'régime fiscal ni des prélèvements sociaux (17,2 %).',
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.results});

  final ScenarioResults results;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 480 ? 2 : 1;
        return GridView.count(
          crossAxisCount: crossCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: crossCount == 2 ? 2.4 : 4.0,
          children: [
            _KpiTile(
              label: 'Mensualité totale',
              value: MoneyFormat.formatEurosFromCents(
                results.loanMonthlyPaymentCents,
              ),
              subtitle: '/mois',
            ),
            _KpiTile(
              label: 'Loyer net annuel',
              value: MoneyFormat.formatEurosFromCents(
                results.annualRentNetCents,
              ),
              subtitle: 'vacance 5 % déduite',
            ),
            _KpiTile(
              label: 'Cash-flow mensuel',
              value: MoneyFormat.formatEurosFromCents(
                results.monthlyCashflowBeforeTaxCents,
              ),
              subtitle: 'avant impôt',
              highlight: _cashflowColor(
                context,
                results.monthlyCashflowBeforeTaxCents,
              ),
            ),
            _KpiTile(
              label: 'Rendement brut',
              value:
                  '${results.yieldGrossPercent.toStringAsFixed(2).replaceAll('.', ',')} %',
              highlight: _yieldColor(context, results.yieldGrossPercent),
            ),
            _KpiTile(
              label: 'Rendement net',
              value:
                  '${results.yieldNetPercent.toStringAsFixed(2).replaceAll('.', ',')} %',
              subtitle: 'avant impôt',
              highlight: _yieldColor(context, results.yieldNetPercent),
            ),
            _KpiTile(
              label: 'Total intérêts versés',
              value: MoneyFormat.formatEurosFromCents(
                results.totalInterestPaidCents,
              ),
            ),
            _KpiTile(
              label: 'Coût total crédit',
              value: MoneyFormat.formatEurosFromCents(
                results.totalLoanCostCents,
              ),
              subtitle: 'capital + intérêts + assurance',
            ),
            _KpiTile(
              label: 'Valeur estimée à terme',
              value: MoneyFormat.formatEurosFromCents(
                results.estimatedValueAtEndCents,
              ),
              subtitle: '+1,5 %/an sur 20 ans',
            ),
          ],
        );
      },
    );
  }

  Color? _yieldColor(BuildContext context, double percent) {
    final cs = Theme.of(context).colorScheme;
    if (percent < 5) return cs.error;
    if (percent < 7) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  Color? _cashflowColor(BuildContext context, int cents) {
    if (cents < 0) return Theme.of(context).colorScheme.error;
    if (cents == 0) return Colors.orange.shade700;
    return Colors.green.shade700;
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    this.subtitle,
    this.highlight,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: highlight,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _DisclaimerTile extends StatelessWidget {
  const _DisclaimerTile({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
