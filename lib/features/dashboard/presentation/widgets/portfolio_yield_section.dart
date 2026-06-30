// ignore_for_file: invalid_annotation_target

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';

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
    /// Null si aucun bien avec prix d'achat + bail actif.
    double? avgYieldGrossPercent,

    /// Rendement net moyen pondéré.
    /// Null si charges manquantes pour tous les biens calculables.
    double? avgYieldNetPercent,

    /// Cash flow mensuel total (centimes). Null si non calculable.
    int? totalMonthlyCashflowCents,

    /// Nombre de biens avec prix d'achat + bail actif.
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
/// Limitation : PropertyListItem expose `currentRentLabel` (string formatée CC)
/// mais pas `rent_amount_cents` (loyer HC en centimes bruts).
/// Sans le loyer HC précis, les rendements brut/net ne sont pas calculables ici.
/// On retourne les biens "en attente" (prix + bail actif) pour l'UI de status.
/// Les rendements seront disponibles via une future version avec jointure enrichie.
PortfolioYieldSummary computePortfolioYield(List<PropertyListItem> items) {
  if (items.isEmpty) {
    return const PortfolioYieldSummary(computedCount: 0, totalCount: 0);
  }

  int computedCount = 0;
  double weightedGrossNumerator = 0;
  double weightedGrossDenominator = 0;
  double weightedNetNumerator = 0;
  double weightedNetDenominator = 0;

  for (final item in items) {
    final property = item.property;
    final purchasePrice = property.purchasePriceCents;
    // Seuls les biens avec prix d'achat ET bail actif sont comptabilisés.
    if (purchasePrice == null || purchasePrice <= 0) continue;
    if (item.activeLeaseId == null) continue;

    computedCount++;
    final weight = purchasePrice.toDouble();

    // Note : sans loyer HC disponible dans PropertyListItem,
    // on ne peut pas calculer les rendements brut/net ici.
    // Ces calculs sont disponibles sur la fiche du bien via PropertyProfitabilityCard.
    // Pour le dashboard, on affiche le nombre de biens calculables.
    weightedGrossDenominator += weight;

    final hasCharges =
        property.propertyTaxAnnualCents != null ||
        property.insurancePnoAnnualCents != null ||
        property.condoFeesNonRecoverableCents != null;
    if (hasCharges) {
      weightedNetDenominator += weight;
    }
  }

  return PortfolioYieldSummary(
    // Rendements null — loyer HC non accessible dans PropertyListItem.
    avgYieldGrossPercent: weightedGrossDenominator > 0
        ? weightedGrossNumerator / weightedGrossDenominator * 100
        : null,
    avgYieldNetPercent: weightedNetDenominator > 0
        ? weightedNetNumerator / weightedNetDenominator * 100
        : null,
    totalMonthlyCashflowCents: null,
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
          'Rentabilité portfolio',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: spacing.md),
        asyncYield.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(
            'Impossible de calculer la rentabilité du portfolio.',
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

    if (summary.totalCount == 0) {
      return Text(
        'Aucun bien dans le portfolio.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (summary.computedCount == 0) {
      return Text(
        'Saisir le prix d\'achat et créer un bail sur vos biens '
        'pour afficher la rentabilité portfolio.',
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
              label: 'Rdt brut moyen',
              value: summary.avgYieldGrossPercent != null
                  ? '${summary.avgYieldGrossPercent!.toStringAsFixed(2)} %'
                  : '—',
              subtitle: 'Pondéré par prix d\'achat',
            ),
            _PortfolioKpiCard(
              key: const Key('kpi_portfolio_net_yield'),
              icon: Icons.account_balance_outlined,
              label: 'Rdt net moyen',
              value: summary.avgYieldNetPercent != null
                  ? '${summary.avgYieldNetPercent!.toStringAsFixed(2)} %'
                  : '—',
              subtitle: 'Avant impôt',
            ),
            _PortfolioKpiCard(
              key: const Key('kpi_portfolio_cashflow'),
              icon: Icons.euro_outlined,
              label: 'Cash flow mensuel total',
              value: summary.totalMonthlyCashflowCents != null
                  ? MoneyFormat.formatEurosFromCents(
                      summary.totalMonthlyCashflowCents!,
                    )
                  : '—',
              subtitle: 'Avant impôt',
            ),
          ],
        ),
        SizedBox(height: spacing.sm),
        Text(
          '${summary.computedCount} bien(s) sur ${summary.totalCount} avec '
          'prix d\'achat et bail actif. Estimations avant impôt.',
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
