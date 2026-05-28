import 'package:flutter/material.dart';

/// Affiche les baux liés à un locataire sous forme de liste de cards.
///
/// Données brutes : `List<Map<String, dynamic>>` issus de
/// `TenantRepository.listLeasesForTenant()`.
/// Sera refactoré en FEAT-005 pour utiliser le modèle `Lease` typé.
///
/// Colonnes disponibles : id, property_id, start_date, end_date, status,
/// rent_amount_cents.
class TenantLeaseSummary extends StatelessWidget {
  const TenantLeaseSummary({super.key, required this.leases});

  final List<Map<String, dynamic>> leases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (leases.isEmpty) {
      return Text(
        'Aucun bail enregistré pour ce locataire.',
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
    final status = lease['status'] as String? ?? '';
    final startDate = lease['start_date'] as String? ?? '';
    final endDate = lease['end_date'] as String?;
    final rentCents = lease['rent_amount_cents'] as int? ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(status: status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatPeriod(startDate, endDate),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${(rentCents / 100).toStringAsFixed(2).replaceAll('.', ',')} €/mois',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Voir le bail (disponible après FEAT-005)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPeriod(String startDate, String? endDate) {
    final start = _formatDate(startDate);
    if (endDate == null || endDate.isEmpty) {
      return 'Du $start (CDI)';
    }
    return 'Du $start au ${_formatDate(endDate)}';
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    final parts = isoDate.split('-');
    if (parts.length < 3) return isoDate;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      'active' => ('Actif', theme.colorScheme.primary),
      'terminated' => ('Terminé', theme.colorScheme.outline),
      'archived' => ('Archivé', theme.colorScheme.outline),
      _ => (status, theme.colorScheme.outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
