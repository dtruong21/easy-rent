import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../leases/domain/lease_status.dart';

/// Affiche les baux liés à un locataire sous forme de liste de cards.
///
/// Données brutes : `List<Map<String, dynamic>>` issus de
/// `TenantRepository.listLeasesForTenant()`.
///
/// Colonnes disponibles : id, property_id, start_date, end_date, status,
/// rent_amount_cents.
///
/// Chaque entrée est cliquable et navigue vers `/leases/:id` (FEAT-005).
class TenantLeaseSummary extends StatelessWidget {
  const TenantLeaseSummary({super.key, required this.leases});

  final List<Map<String, dynamic>> leases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (leases.isEmpty) {
      return Text(
        context.l10n.tenantsNoLeaseForTenant,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      children: leases.map((lease) => _LeaseItem(lease: lease)).toList(),
    );
  }
}

class _LeaseItem extends StatelessWidget {
  const _LeaseItem({required this.lease});

  final Map<String, dynamic> lease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final leaseId = lease['id'] as String? ?? '';
    final status = lease['status'] as String? ?? '';
    final startDate = lease['start_date'] as String? ?? '';
    final endDate = lease['end_date'] as String?;
    final rentCents = lease['rent_amount_cents'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: leaseId.isNotEmpty
            ? () => context.push('/leases/$leaseId')
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _leaseStatusPill(context, status),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatPeriod(l10n, startDate, endDate),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.tenantsLeaseRentPerMonth(
                        MoneyFormat.formatEurosFromCents(rentCents),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (leaseId.isNotEmpty)
                      Text(
                        l10n.tenantsViewLeaseButton,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                  ],
                ),
              ),
              if (leaseId.isNotEmpty)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPeriod(
    AppLocalizations l10n,
    String startDate,
    String? endDate,
  ) {
    final start = FrenchDate.formatIsoString(startDate);
    if (endDate == null || endDate.isEmpty) {
      return l10n.tenantsLeasePeriodOpenEnded(start);
    }
    return l10n.tenantsLeasePeriodFixed(
      start,
      FrenchDate.formatIsoString(endDate),
    );
  }
}

/// Construit un [StatusPill] depuis la valeur SQL brute du statut de bail.
StatusPill _leaseStatusPill(BuildContext context, String sqlStatus) {
  final l10n = context.l10n;
  final status = LeaseStatus.fromSql(sqlStatus);
  final (label, tone) = switch (status) {
    LeaseStatus.active => (
      l10n.tenantsLeaseStatusActive,
      StatusPillTone.success,
    ),
    LeaseStatus.terminated => (
      l10n.tenantsLeaseStatusTerminated,
      StatusPillTone.neutral,
    ),
    LeaseStatus.archived => (
      l10n.tenantsLeaseStatusArchived,
      StatusPillTone.neutral,
    ),
  };
  return StatusPill(label: label, tone: tone);
}
