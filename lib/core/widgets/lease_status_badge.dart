import 'package:flutter/material.dart';

import '../../features/leases/domain/lease_status.dart';

/// Badge coloré affichant le statut d'un bail.
///
/// Extrait du widget privé `_StatusBadge` de `tenant_lease_summary.dart`
/// pour réutilisation dans [LeaseCard], [LeaseDetailPage] et
/// [TenantLeaseSummary].
///
/// Palette :
/// - `active`     → `colorScheme.primary` (bleu/violet selon le thème)
/// - `terminated` → `colorScheme.outline` (gris)
/// - `archived`   → `colorScheme.outline` (gris — valeur défensive)
@Deprecated(
  'Use StatusPill from lib/core/ui/cards/status_pill.dart — migration in Phase 1',
)
class LeaseStatusBadge extends StatelessWidget {
  const LeaseStatusBadge({super.key, required this.status});

  /// Construit un badge depuis la valeur SQL brute du statut.
  ///
  /// Utilisé par les consommateurs qui reçoivent `Map<String,dynamic>['status']`
  /// (ex. [TenantLeaseSummary]). Les valeurs inconnues sont traitées comme
  /// [LeaseStatus.archived] (comportement défensif de [LeaseStatus.fromSql]).
  LeaseStatusBadge.fromSql(String sqlStatus, {super.key})
    : status = LeaseStatus.fromSql(sqlStatus);

  /// Statut typé du bail.
  final LeaseStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      LeaseStatus.active => ('Actif', theme.colorScheme.primary),
      LeaseStatus.terminated => ('Terminé', theme.colorScheme.outline),
      LeaseStatus.archived => ('Archivé', theme.colorScheme.outline),
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
