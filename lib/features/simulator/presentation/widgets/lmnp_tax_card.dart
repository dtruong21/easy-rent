import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/store_billing.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/money_format.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/plan_level.dart';
import '../../domain/investment_scenario.dart';
import '../../domain/lmnp_tax_simulation.dart';

/// Carte « Fiscalité LMNP » (FEAT-061) : micro-BIC vs réel sur 10 ans.
/// Réservée au palier Pro ; les autres voient une variante verrouillée.
class LmnpTaxCard extends ConsumerWidget {
  const LmnpTaxCard({super.key, required this.scenario});

  final InvestmentScenario scenario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;
    final tierAsync = ref.watch(landlordTierProvider);
    // Tier pas encore résolu : rien, pour ne pas montrer le cadenas à un Pro.
    if (!tierAsync.hasValue) return const SizedBox.shrink();
    final isPro = tierAsync.value?.plan.atLeast(PlanLevel.pro) ?? false;
    final title = Text(
      l10n.simulatorLmnpCardTitle,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    if (!isPro) {
      return Card(
        key: const Key('lmnp_locked'),
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: 8),
                  title,
                ],
              ),
              SizedBox(height: spacing.sm),
              Text(l10n.simulatorLmnpLockedBody),
              if (canOfferUpgrade) ...[
                SizedBox(height: spacing.md),
                FilledButton(
                  key: const Key('lmnp_upgrade_button'),
                  onPressed: () => context.push('/pro'),
                  child: Text(l10n.simulatorLmnpUpgradeButton),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final sim = simulateLmnpTax(scenario);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget warning(Key key, String text) => Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: muted)),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            Text(sim.rules.label, style: muted),
            SizedBox(height: spacing.md),
            LayoutBuilder(
              builder: (context, c) {
                final micro = _RegimeColumn(
                  key: const Key('lmnp_micro_column'),
                  regime: LmnpRegime.micro,
                  sim: sim,
                );
                final reel = _RegimeColumn(
                  key: const Key('lmnp_reel_column'),
                  regime: LmnpRegime.reel,
                  sim: sim,
                );
                return c.maxWidth > 480
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: micro),
                          SizedBox(width: spacing.md),
                          Expanded(child: reel),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          micro,
                          SizedBox(height: spacing.md),
                          reel,
                        ],
                      );
              },
            ),
            ExpansionTile(
              key: const Key('lmnp_yearly_toggle'),
              tilePadding: EdgeInsets.zero,
              title: Text(l10n.simulatorLmnpYearlyToggle),
              children: [_YearlyTable(sim: sim)],
            ),
            SizedBox(height: spacing.sm),
            if (sim.lmpAlert)
              warning(
                const Key('lmnp_warning_lmp'),
                l10n.simulatorLmnpWarningLmp,
              ),
            warning(
              const Key('lmnp_warning_resale'),
              l10n.simulatorLmnpWarningResale,
            ),
            warning(
              const Key('lmnp_warning_reform'),
              l10n.simulatorLmnpWarningReform,
            ),
            SizedBox(height: spacing.xs),
            Text(l10n.simulatorLmnpDisclaimer, style: muted),
          ],
        ),
      ),
    );
  }
}

class _RegimeColumn extends StatelessWidget {
  const _RegimeColumn({super.key, required this.regime, required this.sim});

  final LmnpRegime regime;
  final LmnpTaxSimulation sim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isMicro = regime == LmnpRegime.micro;
    final r = isMicro ? sim.micro : sim.reel;
    final prefix = isMicro ? 'lmnp_micro' : 'lmnp_reel';
    final isBest = sim.best == regime;

    Widget line(String label, int cents, {Key? key, bool strong = false}) =>
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text(
                MoneyFormat.formatEurosFromCents(cents),
                key: key,
                style: strong
                    ? theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )
                    : theme.textTheme.bodyMedium,
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isBest
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                isMicro
                    ? l10n.simulatorLmnpMicroTitle
                    : l10n.simulatorLmnpReelTitle,
                style: theme.textTheme.titleSmall,
              ),
              if (isBest)
                Chip(
                  key: const Key('lmnp_best_badge'),
                  label: Text(l10n.simulatorLmnpBestBadge),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (!r.available)
            Padding(
              key: const Key('lmnp_micro_unavailable'),
              padding: const EdgeInsets.only(top: 6),
              child: Text(l10n.simulatorLmnpMicroUnavailable),
            )
          else ...[
            line(l10n.simulatorLmnpYear1Tax, r.years.first.totalTaxCents),
            line(
              l10n.simulatorLmnpTotalTax,
              r.totalTaxCents,
              key: Key('${prefix}_total'),
              strong: true,
            ),
            line(
              l10n.simulatorLmnpCashflowAfterTax,
              r.totalCashflowAfterTaxCents,
            ),
          ],
        ],
      ),
    );
  }
}

class _YearlyTable extends StatelessWidget {
  const _YearlyTable({required this.sim});

  final LmnpTaxSimulation sim;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fmt = MoneyFormat.formatEurosFromCents;
    return Column(
      key: const Key('lmnp_yearly_table'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, r) in [
          (l10n.simulatorLmnpMicroTitle, sim.micro),
          (l10n.simulatorLmnpReelTitle, sim.reel),
        ])
          if (r.available) ...[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                columns: [
                  DataColumn(label: Text(l10n.simulatorLmnpColYear)),
                  DataColumn(label: Text(l10n.simulatorLmnpColTaxable)),
                  DataColumn(label: Text(l10n.simulatorLmnpColIncomeTax)),
                  DataColumn(label: Text(l10n.simulatorLmnpColSocial)),
                  DataColumn(label: Text(l10n.simulatorLmnpColCashflow)),
                ],
                rows: [
                  for (final y in r.years)
                    DataRow(
                      cells: [
                        DataCell(Text('${y.year}')),
                        DataCell(Text(fmt(y.taxableCents))),
                        DataCell(Text(fmt(y.incomeTaxCents))),
                        DataCell(Text(fmt(y.socialCents))),
                        DataCell(Text(fmt(y.cashflowAfterTaxCents))),
                      ],
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}
