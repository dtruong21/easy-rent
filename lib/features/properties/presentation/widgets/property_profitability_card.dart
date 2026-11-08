import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/finance/profitability_snapshot.dart';
import '../../../../core/finance/real_expense_charges.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/money_format.dart';
import '../../application/active_lease_provider.dart';
import '../../application/property_detail_provider.dart';
import '../../application/property_real_charges_provider.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../domain/property.dart';

/// Carte de rentabilité affichée sur [PropertyDetailPage].
///
/// 3 états :
/// - **Computable** : 3 KPIs (rendement brut, rendement net, cash flow /mois).
/// - **Données manquantes** : CTA "Modifier le bien".
/// - **Bien vacant** : CTA "Créer un bail".
///
/// Inclut un disclaimer légal "Estimation avant impôt".
class PropertyProfitabilityCard extends ConsumerWidget {
  const PropertyProfitabilityCard({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProperty = ref.watch(propertyDetailProvider(propertyId));
    final asyncRent = ref.watch(activeLeaseRentProvider(propertyId));
    final asyncRealCharges = ref.watch(propertyRealChargesProvider(propertyId));

    return asyncProperty.when(
      loading: () => const _LoadingCard(),
      error: (e, _) => const SizedBox.shrink(),
      data: (property) => asyncRent.when(
        loading: () => const _LoadingCard(),
        error: (e, _) => const SizedBox.shrink(),
        data: (monthlyRentHcCents) => _ProfitabilityContent(
          property: property,
          monthlyRentHcCents: monthlyRentHcCents,
          propertyId: propertyId,
          // Repli gracieux sur le prévisionnel si la lecture des dépenses
          // échoue ou charge encore — supplémentaire, pas essentiel : ne
          // doit jamais bloquer l'affichage de la carte rentabilité.
          realCharges:
              asyncRealCharges.valueOrNull ?? PropertyRealCharges.empty,
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.propertiesProfitabilityTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

class _ProfitabilityContent extends StatelessWidget {
  const _ProfitabilityContent({
    required this.property,
    required this.monthlyRentHcCents,
    required this.propertyId,
    required this.realCharges,
  });

  final Property property;
  final int? monthlyRentHcCents;
  final String propertyId;
  final PropertyRealCharges realCharges;

  @override
  Widget build(BuildContext context) {
    final snapshot = computeSnapshotForProperty(
      property: property,
      monthlyRentHcCents: monthlyRentHcCents,
      realCharges: realCharges,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.propertiesProfitabilityTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (monthlyRentHcCents == null)
              _VacantState(propertyId: propertyId)
            else if (!snapshot.isComputable ||
                snapshot.missingFields.isNotEmpty)
              _MissingDataState(propertyId: propertyId)
            else
              _KpiState(snapshot: snapshot),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// État : bien vacant — aucun bail actif
// ---------------------------------------------------------------------------

class _VacantState extends StatelessWidget {
  const _VacantState({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.home_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.propertiesProfitabilityVacantMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('btn_create_lease_from_profitability'),
          icon: const Icon(Icons.add),
          label: Text(context.l10n.propertiesCreateLease),
          onPressed: () =>
              context.push('/leases/new', extra: {'propertyId': propertyId}),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// État : données manquantes (pas de prix d'achat)
// ---------------------------------------------------------------------------

class _MissingDataState extends StatelessWidget {
  const _MissingDataState({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.propertiesProfitabilityMissingDataMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('btn_edit_property_from_profitability'),
          icon: const Icon(Icons.edit_outlined),
          label: Text(context.l10n.propertiesEditPropertyButton),
          onPressed: () => context.push('/properties/$propertyId/edit'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// État : données complètes — 3 KPI cards
// ---------------------------------------------------------------------------

class _KpiState extends StatelessWidget {
  const _KpiState({required this.snapshot});

  final ProfitabilitySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (snapshot.yieldGrossPercent != null)
              _YieldKpiChip(
                label: l10n.propertiesProfitabilityYieldGross,
                percent: snapshot.yieldGrossPercent!,
              ),
            if (snapshot.yieldNetPercent != null)
              _YieldKpiChip(
                label: l10n.propertiesProfitabilityYieldNet,
                percent: snapshot.yieldNetPercent!,
              ),
            if (snapshot.monthlyCashflowBeforeTaxCents != null)
              _CashflowChip(cents: snapshot.monthlyCashflowBeforeTaxCents!),
            if (snapshot.loanMonthlyPaymentCents != null)
              _InfoChip(
                label: l10n.propertiesProfitabilityLoanPayment,
                value: MoneyFormat.formatEurosFromCents(
                  snapshot.loanMonthlyPaymentCents!,
                ),
              ),
          ],
        ),
        if (snapshot.yieldNetPercent == null &&
            snapshot.yieldGrossPercent != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.propertiesProfitabilityNetNotComputable,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (snapshot.monthlyCashflowBeforeTaxCents != null &&
            snapshot.cashflowRealChargesCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            l10n.propertiesProfitabilityCashflowRealBasis(
              snapshot.cashflowRealChargesCount,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          l10n.propertiesProfitabilityDisclaimer,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _YieldKpiChip extends StatelessWidget {
  const _YieldKpiChip({required this.label, required this.percent});

  final String label;
  final double percent;

  Color _color(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final appColors =
        Theme.of(context).extension<AppColors>() ?? AppColors.light;
    if (percent < 5) return colors.error;
    if (percent < 7) return appColors.warning.solid;
    return appColors.success.solid;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(
            '${percent.toStringAsFixed(2)} %',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashflowChip extends StatelessWidget {
  const _CashflowChip({required this.cents});

  final int cents;

  @override
  Widget build(BuildContext context) {
    final isPositive = cents >= 0;
    final appColors =
        Theme.of(context).extension<AppColors>() ?? AppColors.light;
    final color = isPositive
        ? appColors.success.solid
        : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.propertiesProfitabilityCashflow,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(
            MoneyFormat.formatEurosFromCents(cents),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Formate des rendements en pourcentage pour l'affichage.
String formatYield(double percent) => '${percent.toStringAsFixed(2)} %';

/// Formate un montant en euros à partir de centimes.
String formatMoney(int cents) => MoneyFormat.formatEurosFromCents(cents);
