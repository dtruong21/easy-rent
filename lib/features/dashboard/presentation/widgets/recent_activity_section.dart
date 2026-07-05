import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/cards/card_empty_state.dart';
import '../../../../core/ui/theme/app_radii.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
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
              Text('Activité récente', style: theme.textTheme.titleSmall),
              const Spacer(),
              if (hasMore)
                TextButton(
                  key: const Key('btn_activity_toggle'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Réduire' : 'Voir tout'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            const CardEmptyState(
              icon: Icons.history,
              title: 'Aucune activité récente',
              message: 'Commencez par enregistrer un paiement.',
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
          title: 'Paiement enregistré · $tenantName',
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
          title: 'Quittance générée · $periodLabel',
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
          title: '$categoryLabel · $filename',
          subtitle:
              '${_formatSize(sizeBytes)} · ${FrenchDate.format(occurredAt)}',
          // push() (pas go()) — voir F-1 ci-dessus.
          onTap: () => context.push('/leases/$leaseId'),
        ),
    };
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
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
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: Icon(icon, color: theme.colorScheme.primary, size: 20),
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right, size: 16),
      onTap: onTap,
    );
  }
}
