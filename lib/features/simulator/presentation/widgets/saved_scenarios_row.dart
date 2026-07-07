import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/entity_card.dart';
import '../../../../core/ui/cards/entity_card_density.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../data/investment_scenario_repository.dart';
import '../../domain/investment_scenario.dart';

/// Liste horizontale des scénarios sauvegardés (FEAT-018).
///
/// Affichée en haut de [SimulatorPage] si l'utilisateur a au moins 1 scénario.
/// Chaque carte permet de charger un scénario (/simulator/:id) ou de le
/// supprimer après confirmation.
class SavedScenariosRow extends ConsumerWidget {
  const SavedScenariosRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncScenarios = ref.watch(investmentScenariosListProvider);

    return asyncScenarios.when(
      loading: () => const SizedBox(height: 80, child: _LoadingSkeleton()),
      error: (e, _) => const SizedBox.shrink(),
      data: (scenarios) {
        if (scenarios.isEmpty) return const SizedBox.shrink();
        final spacing =
            Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.simulatorSavedScenariosTitle,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: spacing.sm),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: scenarios.length,
                separatorBuilder: (context2, i) => SizedBox(width: spacing.sm),
                itemBuilder: (context, index) => _ScenarioChip(
                  scenario: scenarios[index],
                  onDelete: () async {
                    final confirmed = await _confirmDelete(
                      context,
                      scenarios[index].name,
                    );
                    if (confirmed && context.mounted) {
                      await ref
                          .read(investmentScenariosListProvider.notifier)
                          .delete(scenarios[index].id);
                    }
                  },
                ),
              ),
            ),
            SizedBox(height: spacing.lg),
          ],
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final l10n = context.l10n;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.simulatorDeleteScenarioDialogTitle),
        content: Text(l10n.simulatorDeleteScenarioDialogContent(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _ScenarioChip extends StatelessWidget {
  const _ScenarioChip({required this.scenario, required this.onDelete});

  final InvestmentScenario scenario;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: EntityCard(
        onTap: () => context.go('/simulator/${scenario.id}'),
        semanticLabel: context.l10n.simulatorLoadScenarioSemanticLabel(
          scenario.name,
        ),
        header: Row(
          children: [
            Expanded(
              child: Text(
                scenario.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: Key('delete_scenario_${scenario.id}'),
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: onDelete,
              tooltip: context.l10n.commonDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        density: EntityCardDensity.compact,
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 2,
      separatorBuilder: (context2, i) => const SizedBox(width: 8),
      itemBuilder: (context2, i) => Container(
        width: 180,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
