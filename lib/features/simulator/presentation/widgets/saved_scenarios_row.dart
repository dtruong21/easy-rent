import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/entity_card.dart';
import '../../../../core/ui/cards/entity_card_density.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/subscription_tier.dart';
import '../../data/investment_scenario_repository.dart';
import '../../domain/investment_scenario.dart';

/// Liste horizontale des scénarios sauvegardés (FEAT-018) + mode sélection
/// pour la comparaison Pro (FEAT-055).
///
/// Comportements :
/// - Hors mode sélection : tap sur une carte → charge le scénario ; icône
///   corbeille pour supprimer après confirmation.
/// - En mode sélection : tap → toggle la sélection (0-3 max), icône corbeille
///   masquée, un CTA « Comparer les N » navigue vers `/simulator/compare?ids=…`.
/// - Bouton « Comparer » masqué si < 2 scénarios ; verrouillé (upsell Pro) si
///   le landlord n'est pas au palier `paid`.
class SavedScenariosRow extends ConsumerStatefulWidget {
  const SavedScenariosRow({super.key});

  static const int _maxSelection = 3;
  static const int _minSelection = 2;

  @override
  ConsumerState<SavedScenariosRow> createState() => _SavedScenariosRowState();
}

class _SavedScenariosRowState extends ConsumerState<SavedScenariosRow> {
  bool _selectionMode = false;

  /// Le literal `<String>{}` est un LinkedHashSet — l'ordre d'insertion est
  /// préservé, ce qui garantit que la première case cochée devient la
  /// colonne « référence » de la comparaison.
  final Set<String> _selectedIds = <String>{};

  void _enterSelectionMode() =>
      setState(() => _selectionMode = true);

  void _exitSelectionMode() => setState(() {
    _selectionMode = false;
    _selectedIds.clear();
  });

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        if (_selectedIds.length >= SavedScenariosRow._maxSelection) return;
        _selectedIds.add(id);
      }
    });
  }

  void _openComparison() {
    if (_selectedIds.length < SavedScenariosRow._minSelection) return;
    final ids = _selectedIds.join(',');
    context.push('/simulator/compare?ids=$ids');
  }

  @override
  Widget build(BuildContext context) {
    final asyncScenarios = ref.watch(investmentScenariosListProvider);
    final isPaid =
        ref.watch(landlordTierProvider).valueOrNull?.tier ==
        SubscriptionTier.paid;

    return asyncScenarios.when(
      loading: () => const SizedBox(height: 80, child: _LoadingSkeleton()),
      error: (e, _) => const SizedBox.shrink(),
      data: (scenarios) {
        if (scenarios.isEmpty) return const SizedBox.shrink();
        // Sortie propre du mode sélection si on descend sous 2 scénarios
        // (soft-delete pendant la session).
        if (_selectionMode &&
            scenarios.length < SavedScenariosRow._minSelection) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _exitSelectionMode();
          });
        }
        final theme = Theme.of(context);
        final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.simulatorSavedScenariosTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _CompareScenariosToggle(
                  scenariosCount: scenarios.length,
                  isPaid: isPaid,
                  selectionMode: _selectionMode,
                  selectedCount: _selectedIds.length,
                  onEnterSelection: _enterSelectionMode,
                  onCancelSelection: _exitSelectionMode,
                  onValidate: _openComparison,
                ),
              ],
            ),
            if (_selectionMode &&
                _selectedIds.length < SavedScenariosRow._minSelection)
              Padding(
                padding: EdgeInsets.only(top: spacing.xs),
                child: Text(
                  context.l10n.simulatorCompareSelectionHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            SizedBox(height: spacing.sm),
            SizedBox(
              height: 88,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: scenarios.length,
                separatorBuilder: (_, _) => SizedBox(width: spacing.sm),
                itemBuilder: (context, index) {
                  final s = scenarios[index];
                  return _ScenarioChip(
                    scenario: s,
                    selectionMode: _selectionMode,
                    selected: _selectedIds.contains(s.id),
                    onToggleSelection: () => _toggle(s.id),
                    onDelete: () async {
                      final confirmed = await _confirmDelete(context, s.name);
                      if (confirmed && context.mounted) {
                        await ref
                            .read(investmentScenariosListProvider.notifier)
                            .delete(s.id);
                      }
                    },
                  );
                },
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

/// Bouton d'entrée dans le mode comparaison + boutons de validation/annulation
/// une fois en sélection. Gate Pro miroir de `chargeRegularizationProOnly`
/// (FEAT-044b) : `paid` → actif ; free/anon → grisé + upsell ; < 2 scénarios
/// → masqué (rien à comparer, pas d'upsell trompeur).
class _CompareScenariosToggle extends StatelessWidget {
  const _CompareScenariosToggle({
    required this.scenariosCount,
    required this.isPaid,
    required this.selectionMode,
    required this.selectedCount,
    required this.onEnterSelection,
    required this.onCancelSelection,
    required this.onValidate,
  });

  final int scenariosCount;
  final bool isPaid;
  final bool selectionMode;
  final int selectedCount;
  final VoidCallback onEnterSelection;
  final VoidCallback onCancelSelection;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    if (scenariosCount < SavedScenariosRow._minSelection) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final l10n = context.l10n;

    if (selectionMode) {
      final canValidate =
          selectedCount >= SavedScenariosRow._minSelection &&
          selectedCount <= SavedScenariosRow._maxSelection;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: const Key('compare_toggle_cancel'),
            onPressed: onCancelSelection,
            child: Text(l10n.commonCancel),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('compare_toggle_validate'),
            onPressed: canValidate ? onValidate : null,
            child: Text(l10n.simulatorCompareValidate(selectedCount)),
          ),
        ],
      );
    }

    if (!isPaid) {
      return InkWell(
        key: const Key('compare_toggle_pro_only'),
        onTap: () => context.go('/pro'),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.simulatorCompareButton,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return TextButton.icon(
      key: const Key('compare_toggle_button'),
      onPressed: onEnterSelection,
      icon: const Icon(Icons.compare_arrows, size: 18),
      label: Text(l10n.simulatorCompareButton),
    );
  }
}

class _ScenarioChip extends StatelessWidget {
  const _ScenarioChip({
    required this.scenario,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelection,
    required this.onDelete,
  });

  final InvestmentScenario scenario;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelection;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = EntityCard(
      onTap: selectionMode
          ? onToggleSelection
          : () => context.go('/simulator/${scenario.id}'),
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
            if (selectionMode)
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                key: Key('chip_select_${scenario.id}'),
                size: 18,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              )
            else
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
    );
    return SizedBox(
      width: 180,
      child: selected
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
              child: card,
            )
          : card,
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
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, _) => Container(
        width: 180,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
