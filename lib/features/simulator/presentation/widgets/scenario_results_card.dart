import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/ui/theme/app_colors.dart';
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
              context.l10n.simulatorResultsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: spacing.md),
            _KpiGrid(results: results),
            SizedBox(height: spacing.sm),
            _DisclaimerTile(
              icon: Icons.info_outline,
              text: context.l10n.simulatorResultsTaxDisclaimer,
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
              label: context.l10n.simulatorKpiMonthlyPaymentLabel,
              value: MoneyFormat.formatEurosFromCents(
                results.loanMonthlyPaymentCents,
              ),
              subtitle: context.l10n.simulatorKpiPerMonthSuffix,
            ),
            _KpiTile(
              label: context.l10n.simulatorKpiAnnualRentNetLabel,
              value: MoneyFormat.formatEurosFromCents(
                results.annualRentNetCents,
              ),
              subtitle: context.l10n.simulatorKpiVacancyDeductedSubtitle,
            ),
            _KpiTile(
              label: context.l10n.simulatorKpiMonthlyCashflowLabel,
              value: MoneyFormat.formatEurosFromCents(
                results.monthlyCashflowBeforeTaxCents,
              ),
              subtitle: context.l10n.simulatorKpiBeforeTaxSubtitle,
              highlight: _cashflowColor(
                context,
                results.monthlyCashflowBeforeTaxCents,
              ),
            ),
            _KpiTile(
              label: context.l10n.simulatorKpiGrossYieldLabel,
              value:
                  '${results.yieldGrossPercent.toStringAsFixed(2).replaceAll('.', ',')} %',
              highlight: _yieldColor(context, results.yieldGrossPercent),
            ),
            _KpiTile(
              label: context.l10n.simulatorKpiNetYieldLabel,
              value:
                  '${results.yieldNetPercent.toStringAsFixed(2).replaceAll('.', ',')} %',
              subtitle: context.l10n.simulatorKpiBeforeTaxSubtitle,
              highlight: _yieldColor(context, results.yieldNetPercent),
            ),
            _KpiTile(
              label: context.l10n.simulatorKpiTotalInterestLabel,
              value: MoneyFormat.formatEurosFromCents(
                results.totalInterestPaidCents,
              ),
            ),
            _KpiTile(
              label: context.l10n.simulatorKpiTotalLoanCostLabel,
              value: MoneyFormat.formatEurosFromCents(
                results.totalLoanCostCents,
              ),
              subtitle: context.l10n.simulatorKpiLoanCostBreakdownSubtitle,
            ),
            _KpiTile(
              label: context.l10n.simulatorKpiEstimatedValueLabel,
              value: MoneyFormat.formatEurosFromCents(
                results.estimatedValueAtEndCents,
              ),
              subtitle: context.l10n.simulatorKpiAppreciationSubtitle,
            ),
          ],
        );
      },
    );
  }

  Color? _yieldColor(BuildContext context, double percent) {
    final cs = Theme.of(context).colorScheme;
    final appColors =
        Theme.of(context).extension<AppColors>() ?? AppColors.light;
    if (percent < 5) return cs.error;
    if (percent < 7) return appColors.warning.solid;
    return appColors.success.solid;
  }

  Color? _cashflowColor(BuildContext context, int cents) {
    final appColors =
        Theme.of(context).extension<AppColors>() ?? AppColors.light;
    if (cents < 0) return Theme.of(context).colorScheme.error;
    if (cents == 0) return appColors.warning.solid;
    return appColors.success.solid;
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
