import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import 'monthly_cashflow_chart.dart';

/// Enveloppe repliable (fermée par défaut) autour de [MonthlyCashflowChart].
///
/// `maintainState: false` → l'enfant (et donc `monthlyCashflowProvider`) n'est
/// construit qu'au premier dépliage : le graphe ne charge rien tant que la
/// carte reste fermée.
class CollapsibleCashflowSection extends StatelessWidget {
  const CollapsibleCashflowSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radii = theme.extension<AppRadii>() ?? const AppRadii();
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Theme(
          // Retire les traits par défaut de l'ExpansionTile pour coller à la carte.
          data: theme.copyWith(dividerColor: theme.colorScheme.surface),
          child: ExpansionTile(
            key: const Key('cashflow_expansion'),
            initiallyExpanded: false,
            maintainState: false,
            tilePadding: EdgeInsets.symmetric(
              horizontal: spacing.lg,
              vertical: spacing.xs,
            ),
            title: Text(
              l10n.dashboardCashflowCollapsibleTitle,
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text(
              l10n.dashboardCashflowCollapsibleSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            childrenPadding: EdgeInsets.fromLTRB(
              spacing.lg,
              0,
              spacing.lg,
              spacing.lg,
            ),
            children: const [MonthlyCashflowChart()],
          ),
        ),
      ),
    );
  }
}
