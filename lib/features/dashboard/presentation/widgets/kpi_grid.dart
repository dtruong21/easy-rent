import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/money_format.dart';
import '../../application/dashboard_portfolio_kpis_provider.dart';
import 'kpi_card.dart';

/// Grille responsive de 2 KPI : occupation, patrimoine.
///
/// Occupation et patrimoine viennent de [dashboardPortfolioKpisProvider]
/// (dérivé de la liste des biens, zéro requête propre). Les compteurs
/// loyers/retards/renouvellements ont été retirés — ils font désormais
/// doublon avec le panneau « À traiter / À venir » (encaissements, retards,
/// baux finissant en détail).
class KpiGrid extends ConsumerWidget {
  const KpiGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width > 600 ? 2 : 1;
        const ratio = 1.6;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          childAspectRatio: ratio,
          crossAxisSpacing: spacing.md,
          mainAxisSpacing: spacing.md,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: _buildCards(context, ref),
        );
      },
    );
  }

  List<Widget> _buildCards(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;
    final kpis = ref.watch(dashboardPortfolioKpisProvider).valueOrNull;

    // --- Occupation ---
    final String occValue;
    final String occSubtitle;
    final Color occColor;
    if (kpis == null || !kpis.hasProperties) {
      occValue = '—';
      occSubtitle = l10n.dashboardKpiOccupancyNone;
      occColor = colors.neutral.solid;
    } else {
      occValue = '${kpis.occupancyPercent} %';
      final rented = l10n.dashboardKpiOccupancyRented(
        kpis.occupied,
        kpis.total,
      );
      occSubtitle = kpis.vacant > 0
          ? '$rented · ${l10n.dashboardKpiOccupancyVacant(kpis.vacant)}'
          : rented;
      occColor = kpis.vacant > 0 ? colors.warning.solid : colors.success.solid;
    }

    // --- Patrimoine (montant à l'achat, factuel) ---
    final String patValue;
    final String patSubtitle;
    if (kpis == null || !kpis.hasAnyPrice) {
      patValue = '—';
      patSubtitle = l10n.dashboardKpiPatrimonyNone;
    } else {
      patValue = MoneyFormat.formatEurosFromCents(kpis.patrimoineCents);
      patSubtitle = kpis.propertiesWithPrice == kpis.total
          ? l10n.dashboardKpiPatrimonyAtPurchase
          : l10n.dashboardKpiPatrimonyPartial(
              kpis.propertiesWithPrice,
              kpis.total,
            );
    }

    return [
      KpiCard(
        key: const Key('kpi_occupation'),
        icon: Icons.meeting_room_outlined,
        label: l10n.dashboardKpiOccupancyLabel,
        value: occValue,
        subtitle: occSubtitle,
        semanticColor: occColor,
        onTap: () => context.go('/properties'),
      ),
      KpiCard(
        key: const Key('kpi_patrimoine'),
        icon: Icons.account_balance_outlined,
        label: l10n.dashboardKpiPatrimonyLabel,
        value: patValue,
        subtitle: patSubtitle,
        semanticColor: colors.neutral.solid,
        onTap: () => context.go('/properties'),
      ),
    ];
  }
}
