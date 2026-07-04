import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/cards/entity_card.dart';
import '../../../../core/ui/cards/entity_card_header.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/lease.dart';
import '../../domain/lease_list_item.dart';
import 'lease_status_mapper.dart';

/// Card v2 représentant un bail dans la liste.
///
/// Utilise [EntityCard] pour le layout cohérent avec les autres entités.
/// Header : nom du bien + [StatusPill] statut.
/// Body : locataire, période, loyer CC.
/// Footer : boutons "Quittances" et "+ Paiement".
///
/// Le tap sur la carte entière navigue vers le détail du bail.
/// Les boutons footer sont indépendants (hit-testing Flutter natif).
class LeaseCard extends StatelessWidget {
  const LeaseCard({super.key, required this.item, required this.onTap});

  final LeaseListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lease = item.lease;
    final pillData = leaseStatusPill(lease, isLate: item.isLate);

    return EntityCard(
      onTap: onTap,
      semanticLabel: '${item.propertyName} — ${item.tenantDisplayName}',
      header: EntityCardHeader(
        title: Text(
          item.propertyName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusPill(
          tone: pillData.tone,
          label: pillData.label,
          icon: pillData.icon,
          size: StatusPillSize.sm,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LeaseCardRow(
            icon: Icons.person_outline,
            text: item.tenantDisplayName,
          ),
          const SizedBox(height: 4),
          _LeaseCardRow(
            icon: Icons.calendar_today_outlined,
            text: _formatPeriod(lease.startDate, lease.endDate),
          ),
          const SizedBox(height: 4),
          _LeaseCardRow(
            icon: Icons.euro_outlined,
            text:
                '${MoneyFormat.formatEurosFromCents(lease.totalAmountCents)} CC / mois',
          ),
        ],
      ),
      footer: _LeaseCardFooter(leaseId: lease.id),
    );
  }

  String _formatPeriod(DateTime startDate, DateTime? endDate) {
    final start = FrenchDate.format(startDate);
    if (endDate == null) {
      return '$start → CDI';
    }
    final end = FrenchDate.format(endDate);
    final years = (endDate.difference(startDate).inDays / 365.25).round().abs();
    if (years > 0) {
      return '$start → $end ($years an${years > 1 ? 's' : ''})';
    }
    return '$start → $end';
  }
}

// ---------------------------------------------------------------------------
// Widgets privés
// ---------------------------------------------------------------------------

class _LeaseCardRow extends StatelessWidget {
  const _LeaseCardRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LeaseCardFooter extends StatelessWidget {
  const _LeaseCardFooter({required this.leaseId});

  final String leaseId;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        OutlinedButton.icon(
          onPressed: () => context.push('/leases/$leaseId/receipts'),
          icon: const Icon(Icons.receipt_long_outlined, size: 16),
          label: const Text('Quittances'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => context.push('/leases/$leaseId/payments/new'),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Paiement'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
