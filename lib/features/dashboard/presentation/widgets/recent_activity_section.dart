import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/card_empty_state.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/activity_item.dart';

/// Section "Activité récente" du dashboard.
///
/// Affiche les 5 premiers [ActivityItem] repliés ; « Voir tout » déplie sur
/// place le reste de la liste fournie (jusqu'à 30, voir dashboardProvider)
/// et devient « Réduire ». Le bouton est masqué à 5 items ou moins.
/// Si la liste est vide → [CardEmptyState].
class RecentActivitySection extends StatefulWidget {
  const RecentActivitySection({super.key, required this.items});

  final List<ActivityItem> items;

  /// Nombre d'items visibles repliés.
  static const int collapsedCount = 5;

  @override
  State<RecentActivitySection> createState() => _RecentActivitySectionState();
}

class _RecentActivitySectionState extends State<RecentActivitySection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final radii = theme.extension<AppRadii>() ?? const AppRadii();

    final items = widget.items;
    final hasMore = items.length > RecentActivitySection.collapsedCount;
    final visible = _expanded
        ? items
        : items.take(RecentActivitySection.collapsedCount);
    final l10n = context.l10n;

    return Container(
      padding: EdgeInsets.all(spacing.cardPaddingStandard),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radii.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.dashboardRecentActivityTitle,
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              if (hasMore)
                TextButton(
                  key: const Key('btn_activity_toggle'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(
                    _expanded
                        ? l10n.dashboardRecentActivityCollapseButton
                        : l10n.dashboardRecentActivityShowAllButton,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            CardEmptyState(
              icon: Icons.history,
              title: l10n.dashboardRecentActivityEmptyTitle,
              message: l10n.dashboardRecentActivityEmptyMessage,
            )
          else
            ...visible.map((item) => _ActivityTile(item: item)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tiles
// ---------------------------------------------------------------------------

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item});
  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (item) {
      ActivityPaymentRecorded(
        :final paymentId,
        :final leaseId,
        :final tenantName,
        :final amountCents,
        :final occurredAt,
      ) =>
        _Tile(
          icon: Icons.payments_outlined,
          title: l10n.dashboardActivityPaymentRecordedTitle(tenantName),
          subtitle:
              '${MoneyFormat.formatEurosFromCents(amountCents)} · ${FrenchDate.format(occurredAt)}',
          // push() (pas go()) : depuis l'onglet Accueil, on empile la
          // sous-page de la branche Baux sans changer d'onglet — pop() y
          // ramène directement à l'Accueil (F-1, docs/UX_NAVIGATION.md §5).
          onTap: () =>
              context.push('/leases/$leaseId/payments/$paymentId/edit'),
        ),
      ActivityReceiptGenerated(
        receiptId: _,
        :final leaseId,
        :final periodLabel,
        :final totalCents,
        :final occurredAt,
      ) =>
        _Tile(
          icon: Icons.description_outlined,
          title: l10n.dashboardActivityReceiptGeneratedTitle(periodLabel),
          subtitle:
              '${MoneyFormat.formatEurosFromCents(totalCents)} · ${FrenchDate.format(occurredAt)}',
          // push() (pas go()) — voir F-1 ci-dessus.
          onTap: () => context.push('/leases/$leaseId/receipts'),
        ),
      ActivityDocumentUploaded(
        documentId: _,
        :final leaseId,
        :final categoryLabel,
        :final filename,
        :final sizeBytes,
        :final occurredAt,
      ) =>
        _Tile(
          icon: Icons.attach_file_outlined,
          // categoryLabel : valeur brute produite côté data/ (catégorie
          // Firestore, ex. 'bail_signe' ou fallback 'document') — hors
          // périmètre de cette extraction (couplage au module `documents`,
          // cf. notes agent).
          title: '$categoryLabel · $filename',
          subtitle:
              '${_formatSize(sizeBytes, l10n)} · ${FrenchDate.format(occurredAt)}',
          // push() (pas go()) — voir F-1 ci-dessus.
          onTap: () => context.push('/leases/$leaseId'),
        ),
    };
  }

  static String _formatSize(int bytes, AppLocalizations l10n) {
    if (bytes < 1024) return l10n.dashboardActivityFileSizeBytes(bytes);
    if (bytes < 1024 * 1024) {
      return l10n.dashboardActivityFileSizeKilobytes((bytes / 1024).round());
    }
    return l10n.dashboardActivityFileSizeMegabytes(bytes / (1024 * 1024));
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Material(transparency) : le parent (Container à fond coloré dans
    // RecentActivitySection) reste seul responsable du fond visuel ; on
    // fournit juste l'ancêtre Material requis par ListTile pour l'InkWell
    // et pour satisfaire l'assertion Flutter « ListTile dans un
    // DecoratedBox coloré doit avoir un Material entre les deux ».
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 0),
        leading: Icon(icon, color: theme.colorScheme.primary, size: 20),
        title: Text(title, style: theme.textTheme.bodyMedium),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right, size: 16),
        onTap: onTap,
      ),
    );
  }
}
