import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_colors.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../../leases/domain/lease.dart';
import '../../../leases/domain/lease_list_item.dart';
import '../../application/dashboard_action_items_provider.dart';
import '../../domain/dashboard_kpi.dart';

/// Panneau « À traiter / À venir » : encaissements du mois + loyers en retard
/// + baux finissant. Remplace le graphe cash-flow à son emplacement.
class ActionItemsPanel extends ConsumerWidget {
  const ActionItemsPanel({
    super.key,
    required this.loyers,
    required this.docsPendingCount,
  });

  final LoyersMoisKpi loyers;
  final int docsPendingCount;

  static const _maxRows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final radii = theme.extension<AppRadii>() ?? const AppRadii();
    final l10n = context.l10n;
    final async = ref.watch(dashboardActionItemsProvider);
    final items = async.valueOrNull;

    return Container(
      key: const Key('dashboard_action_panel'),
      padding: EdgeInsets.all(spacing.cardPaddingStandard),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollectionBanner(loyers: loyers),
          if (items != null) ...[
            if (items.late.isNotEmpty) ...[
              SizedBox(height: spacing.lg),
              _Section(
                title: l10n.dashboardActionLateSectionTitle,
                rows: items.late,
                keyPrefix: 'action_late',
                viewAllKey: 'action_late_view_all',
                onTapRoute: '/leases?filter=late',
                trailing: (ctx) => _Badge(
                  label: l10n.dashboardActionLateBadge,
                  color:
                      (theme.extension<AppColors>() ?? AppColors.light).danger,
                ),
                subtitle: (i) =>
                    MoneyFormat.formatEurosFromCents(i.lease.totalAmountCents),
              ),
            ],
            if (items.ending.isNotEmpty) ...[
              SizedBox(height: spacing.lg),
              _Section(
                title: l10n.dashboardActionEndingSectionTitle,
                rows: items.ending,
                keyPrefix: 'action_ending',
                viewAllKey: 'action_ending_view_all',
                onTapRoute: '/leases?filter=renewable',
                trailing: null,
                subtitle: (i) => i.lease.endDate != null
                    ? l10n.dashboardActionEndingDate(
                        FrenchDate.format(i.lease.endDate!),
                      )
                    : '',
              ),
            ],
            if (items.isEmpty)
              Padding(
                key: const Key('action_items_empty'),
                padding: EdgeInsets.only(top: spacing.md),
                child: Text(
                  l10n.dashboardActionAllClear,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: (theme.extension<AppColors>() ?? AppColors.light)
                        .success
                        .solid,
                  ),
                ),
              ),
          ] else if (async.hasError)
            Padding(
              padding: EdgeInsets.only(top: spacing.md),
              child: Text(
                l10n.dashboardActionDetailUnavailable,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.only(top: spacing.md),
              child: const Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (docsPendingCount > 0) ...[
            SizedBox(height: spacing.lg),
            Row(
              key: const Key('action_docs_pending'),
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: (theme.extension<AppColors>() ?? AppColors.light)
                      .info
                      .solid,
                ),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: Text(
                    l10n.dashboardActionDocsPending(docsPendingCount),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CollectionBanner extends StatelessWidget {
  const _CollectionBanner({required this.loyers});
  final LoyersMoisKpi loyers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = theme.extension<AppColors>() ?? AppColors.light;
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final due = loyers.dueCents;
    final collected = loyers.encaissedCents;
    final outstanding = (due - collected) > 0 ? (due - collected) : 0;
    final ratio = due > 0 ? (collected / due).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashboardCollectionTitle, style: theme.textTheme.labelLarge),
        SizedBox(height: spacing.xs),
        Text(
          l10n.dashboardCollectionSummary(
            MoneyFormat.formatEurosFromCents(collected),
            MoneyFormat.formatEurosFromCents(due),
          ),
          style: theme.textTheme.bodyMedium,
        ),
        if (due > 0) ...[
          SizedBox(height: spacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              color: outstanding > 0
                  ? colors.warning.solid
                  : colors.success.solid,
            ),
          ),
          SizedBox(height: spacing.xs),
          Text(
            outstanding > 0
                ? l10n.dashboardCollectionOutstanding(
                    MoneyFormat.formatEurosFromCents(outstanding),
                  )
                : l10n.dashboardCollectionAllPaid,
            style: theme.textTheme.bodySmall?.copyWith(
              color: outstanding > 0
                  ? colors.warning.solid
                  : colors.success.solid,
            ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.rows,
    required this.keyPrefix,
    required this.viewAllKey,
    required this.onTapRoute,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final List<LeaseListItem> rows;
  final String keyPrefix;
  final String viewAllKey;
  final String onTapRoute;
  final String Function(LeaseListItem) subtitle;
  final Widget Function(BuildContext)? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;
    final shown = rows.take(ActionItemsPanel._maxRows).toList();
    final overflow = rows.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: spacing.xs),
        // Material(transparency) : le panneau (Container à fond coloré dans
        // ActionItemsPanel) reste seul responsable du fond visuel ; on
        // fournit juste l'ancêtre Material requis par ListTile pour l'InkWell
        // et pour satisfaire l'assertion Flutter « ListTile dans un
        // DecoratedBox coloré doit avoir un Material entre les deux »
        // (même pattern que `recent_activity_section.dart`).
        ...shown.map(
          (i) => Material(
            type: MaterialType.transparency,
            child: ListTile(
              key: Key('${keyPrefix}_${i.lease.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '${i.tenantDisplayName} · ${i.propertyName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                subtitle(i),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: trailing?.call(context),
              onTap: () => context.go(onTapRoute),
            ),
          ),
        ),
        if (overflow > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: Key(viewAllKey),
              onPressed: () => context.go(onTapRoute),
              child: Text(l10n.dashboardActionViewAll(rows.length)),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final StatusColorSet color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
