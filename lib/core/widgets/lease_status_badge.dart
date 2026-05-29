import 'package:flutter/material.dart';

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
class LeaseStatusBadge extends StatelessWidget {
  const LeaseStatusBadge({super.key, required this.status});

  /// Valeur SQL du statut : `'active'`, `'terminated'` ou `'archived'`.
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
