import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/ui/theme/app_spacing.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/plan_matrix.g.dart';
import '../data/investment_scenario_repository.dart';
import '../domain/investment_scenario.dart';
import '../domain/scenario_comparison_view_model.dart';
import 'widgets/scenario_comparison_cards.dart';
import 'widgets/scenario_comparison_table.dart';

/// Écran `/simulator/compare` — comparaison côte-à-côte de 2-3 scénarios
/// sauvegardés (FEAT-055).
///
/// Gate côté page **en plus** du gate d'entrée dans le rail : un deep-link
/// direct par URL (partage, signet, historique) tombe sur l'état verrouillé
/// Pro ici, pas dans le router (décision produit P2, 2026-07-23).
class ScenarioComparisonPage extends ConsumerWidget {
  const ScenarioComparisonPage({super.key, required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hasComparison = ref.watch(
      hasFeatureProvider(PlanFeature.scenarioComparison),
    );

    return Scaffold(
      appBar: AppAppBar(
        title: l10n.simulatorCompareTitle,
        fallbackRoute: '/simulator',
      ),
      body: SafeArea(
        child: !hasComparison
            ? const _ProGatedComparisonBody()
            : _ComparisonBody(ids: ids),
      ),
    );
  }
}

class _ProGatedComparisonBody extends StatelessWidget {
  const _ProGatedComparisonBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('scenario_comparison_pro_gated'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.simulatorCompareProOnly,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/pro'),
                child: Text(l10n.proUpgradeButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparisonBody extends ConsumerWidget {
  const _ComparisonBody({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncScenarios = ref.watch(investmentScenariosListProvider);
    return asyncScenarios.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const _EmptyBody(),
      data: (scenarios) {
        final filtered = _filterInOrder(scenarios, ids);
        if (filtered.length < 2) return const _EmptyBody();
        return _ComparisonContent(scenarios: filtered);
      },
    );
  }

  /// Filtre [scenarios] en préservant l'ordre des [ids] fournis (source de
  /// vérité pour la colonne 0 = référence). Ids inconnus sont simplement omis.
  List<InvestmentScenario> _filterInOrder(
    List<InvestmentScenario> scenarios,
    List<String> ids,
  ) {
    final byId = {for (final s in scenarios) s.id: s};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }
}

class _ComparisonContent extends StatelessWidget {
  const _ComparisonContent({required this.scenarios});

  final List<InvestmentScenario> scenarios;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
    final rows = buildComparisonRows(scenarios, l10n);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Zone de contenu réelle (hors padding horizontal appliqué plus bas)
        // — c'est cette largeur, pas celle de la page, qui doit accueillir
        // les colonnes de la table sans scroll horizontal.
        final contentWidth = constraints.maxWidth - spacing.lg * 2;
        final fitsTable = ScenarioComparisonTable.fitsWidth(
          contentWidth,
          scenarios.length,
        );
        final content = fitsTable
            ? ScenarioComparisonTable(scenarios: scenarios, rows: rows)
            : ScenarioComparisonCards(scenarios: scenarios, rows: rows);
        return SingleChildScrollView(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              content,
              SizedBox(height: spacing.md),
              _TaxDisclaimer(),
            ],
          ),
        );
      },
    );
  }
}

class _TaxDisclaimer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.l10n.simulatorResultsTaxDisclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('scenario_comparison_empty'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.compare_arrows,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.simulatorCompareEmptyTooFew,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/simulator'),
                child: Text(l10n.simulatorCompareBackToRail),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
