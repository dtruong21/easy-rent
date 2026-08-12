// ignore_for_file: invalid_annotation_target

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';

import '../../../../core/finance/profitability_snapshot.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/money_format.dart';
import '../../../properties/application/properties_list_provider.dart';
import '../../../properties/domain/property_list_item.dart';

part 'portfolio_yield_section.freezed.dart';

final _log = Logger('PortfolioYieldSection');

// ---------------------------------------------------------------------------
// Domain
// ---------------------------------------------------------------------------

/// Agrégation de la rentabilité du portfolio.
@freezed
class PortfolioYieldSummary with _$PortfolioYieldSummary {
  const factory PortfolioYieldSummary({
    /// Rendement brut moyen pondéré par prix d'acquisition.
    /// Null si aucun bien avec prix d'achat + bail actif + loyer HC connu.
    double? avgYieldGrossPercent,

    /// Rendement net moyen pondéré.
    /// Null si charges manquantes pour tous les biens calculables.
    double? avgYieldNetPercent,

    /// Cash flow mensuel total (centimes) — somme des biens calculables.
    /// Null si aucun bien n'a de charges ou de prêt renseignés.
    int? totalMonthlyCashflowCents,

    /// Nombre de biens avec prix d'achat + bail actif + loyer HC connu.
    required int computedCount,

    /// Nombre total de biens du portfolio.
    required int totalCount,
  }) = _PortfolioYieldSummary;
}

// ---------------------------------------------------------------------------
// Compute
// ---------------------------------------------------------------------------

/// Calcule la rentabilité agrégée du portfolio.
///
/// Réutilise [computeSnapshotForProperty] — le même moteur que
/// `PropertyProfitabilityCard` sur la fiche d'un bien — pour ne jamais faire
/// diverger les deux calculs.
///
/// Un bien n'entre dans le calcul que s'il a un prix d'achat renseigné,
/// un bail actif ET un loyer HC connu ; c'est [PortfolioYieldSummary.computedCount].
/// Le rendement brut et le rendement net sont des moyennes pondérées par le
/// prix d'achat (biens sans charges renseignées exclus du rendement net,
/// comme sur la fiche individuelle). Le cash flow mensuel est une somme sur
/// les biens dont le cash flow est lui-même calculable (charges ou prêt
/// renseignés).
PortfolioYieldSummary computePortfolioYield(List<PropertyListItem> items) {
  if (items.isEmpty) {
    return const PortfolioYieldSummary(computedCount: 0, totalCount: 0);
  }

  int computedCount = 0;
  double weightedGrossNumerator = 0;
  double weightedGrossDenominator = 0;
  double weightedNetNumerator = 0;
  double weightedNetDenominator = 0;
  int totalMonthlyCashflowCents = 0;
  bool hasCashflow = false;

  for (final item in items) {
    final property = item.property;
    final purchasePrice = property.purchasePriceCents;
    final rentHcCents = item.currentRentHcCents;
    // Seuls les biens avec prix d'achat, bail actif ET loyer HC connu
    // sont comptabilisés — les 3 sont nécessaires au calcul.
    if (purchasePrice == null || purchasePrice <= 0) continue;
    if (item.activeLeaseId == null || rentHcCents == null) continue;

    computedCount++;
    final weight = purchasePrice.toDouble();

    final snapshot = computeSnapshotForProperty(
      property: property,
      monthlyRentHcCents: rentHcCents,
    );

    final grossYield = snapshot.yieldGrossPercent;
    if (grossYield != null) {
      weightedGrossNumerator += grossYield * weight;
      weightedGrossDenominator += weight;
    }

    final netYield = snapshot.yieldNetPercent;
    if (netYield != null) {
      weightedNetNumerator += netYield * weight;
      weightedNetDenominator += weight;
    }

    final cashflow = snapshot.monthlyCashflowBeforeTaxCents;
    if (cashflow != null) {
      totalMonthlyCashflowCents += cashflow;
      hasCashflow = true;
    }
  }

  return PortfolioYieldSummary(
    avgYieldGrossPercent: weightedGrossDenominator > 0
        ? weightedGrossNumerator / weightedGrossDenominator
        : null,
    avgYieldNetPercent: weightedNetDenominator > 0
        ? weightedNetNumerator / weightedNetDenominator
        : null,
    totalMonthlyCashflowCents: hasCashflow ? totalMonthlyCashflowCents : null,
    computedCount: computedCount,
    totalCount: items.length,
  );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Provider du résumé de rentabilité du portfolio.
final portfolioYieldProvider =
    FutureProvider.autoDispose<PortfolioYieldSummary>((ref) async {
      _log.info('portfolioYieldProvider: computing');
      final items = await ref.watch(propertiesListItemsProvider.future);
      return computePortfolioYield(items);
    });

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Section "Rentabilité portfolio" affichée sous la KpiGrid du Dashboard.
class PortfolioYieldSection extends ConsumerWidget {
  const PortfolioYieldSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncYield = ref.watch(portfolioYieldProvider);
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.dashboardPortfolioYieldSectionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: spacing.md),
        asyncYield.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(
            context.l10n.dashboardPortfolioYieldErrorMessage,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          data: (summary) => _PortfolioYieldData(summary: summary),
        ),
      ],
    );
  }
}

class _PortfolioYieldData extends StatelessWidget {
  const _PortfolioYieldData({required this.summary});

  final PortfolioYieldSummary summary;

  @override
  Widget build(BuildContext context) {
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;

    if (summary.totalCount == 0) {
      return Text(
        l10n.dashboardPortfolioYieldEmptyMessage,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (summary.computedCount == 0) {
      return Text(
        l10n.dashboardPortfolioYieldNoComputableMessage,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: spacing.md,
          runSpacing: spacing.md,
          children: [
            _PortfolioKpiCard(
              key: const Key('kpi_portfolio_gross_yield'),
              icon: Icons.trending_up,
              label: l10n.dashboardPortfolioYieldGrossLabel,
              value: summary.avgYieldGrossPercent != null
                  ? '${summary.avgYieldGrossPercent!.toStringAsFixed(2)} %'
                  : '—',
              subtitle: l10n.dashboardPortfolioYieldGrossSubtitle,
            ),
            _PortfolioKpiCard(
              key: const Key('kpi_portfolio_net_yield'),
              icon: Icons.account_balance_outlined,
              label: l10n.dashboardPortfolioYieldNetLabel,
              value: summary.avgYieldNetPercent != null
                  ? '${summary.avgYieldNetPercent!.toStringAsFixed(2)} %'
                  : '—',
              subtitle: l10n.dashboardPortfolioYieldBeforeTaxSubtitle,
            ),
            _PortfolioKpiCard(
              key: const Key('kpi_portfolio_cashflow'),
              icon: Icons.euro_outlined,
              label: l10n.dashboardPortfolioYieldCashflowLabel,
              value: summary.totalMonthlyCashflowCents != null
                  ? MoneyFormat.formatEurosFromCents(
                      summary.totalMonthlyCashflowCents!,
                    )
                  : '—',
              subtitle: l10n.dashboardPortfolioYieldBeforeTaxSubtitle,
            ),
          ],
        ),
        SizedBox(height: spacing.sm),
        Text(
          l10n.dashboardPortfolioYieldFootnote(
            summary.computedCount,
            summary.totalCount,
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _PortfolioKpiCard extends StatelessWidget {
  const _PortfolioKpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
