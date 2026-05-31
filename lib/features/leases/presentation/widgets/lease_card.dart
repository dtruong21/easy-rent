import 'package:flutter/material.dart';

import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/lease_status_badge.dart';
import '../../domain/lease.dart';
import '../../domain/lease_list_item.dart';

/// Card cliquable représentant un bail dans la liste.
///
/// Affiche : nom du bien (gras), nom du locataire, loyer CC formaté,
/// badge statut, période (CDI si end_date null).
class LeaseCard extends StatelessWidget {
  const LeaseCard({super.key, required this.item, required this.onTap});

  final LeaseListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lease = item.lease;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.propertyName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  LeaseStatusBadge(status: lease.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.tenantDisplayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.euro_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${MoneyFormat.formatEurosFromCents(lease.totalAmountCents)}/mois CC',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatPeriod(lease.startDate, lease.endDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPeriod(DateTime startDate, DateTime? endDate) {
    final start = FrenchDate.format(startDate);
    if (endDate == null) {
      return 'Depuis $start (CDI)';
    }
    return 'Du $start au ${FrenchDate.format(endDate)}';
  }
}
