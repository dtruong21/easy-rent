import 'package:flutter/material.dart';

import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../domain/lease.dart';
import '../../domain/lease_status.dart';

/// Résultat du mapping statut bail → pill.
typedef LeaseStatusPillData = ({
  StatusPillTone tone,
  String label,
  IconData icon,
});

/// Mappe un [Lease] vers les propriétés d'affichage d'un [StatusPill].
///
/// Priorité descendante :
/// 1. `active` ET endDate − today < 60 jours → warning "À renouveler"
/// 2. `active` (par défaut) → success "Actif"
/// 3. `terminated` → neutral "Terminé"
/// 4. `archived` → neutral "Archivé"
///
/// Le paramètre [now] est injectable pour les tests (évite la dépendance
/// à `DateTime.now()` dans les tests unitaires).
LeaseStatusPillData leaseStatusPill(Lease lease, {DateTime? now}) {
  final today = now ?? DateTime.now();

  if (lease.status == LeaseStatus.active) {
    final end = lease.endDate;
    if (end != null) {
      final daysUntilEnd = end.difference(today).inDays;
      if (daysUntilEnd < 60) {
        return (
          tone: StatusPillTone.warning,
          label: 'À renouveler',
          icon: Icons.event_repeat_outlined,
        );
      }
    }
    return (
      tone: StatusPillTone.success,
      label: 'Actif',
      icon: Icons.check_circle_outline,
    );
  }

  if (lease.status == LeaseStatus.terminated) {
    return (
      tone: StatusPillTone.neutral,
      label: 'Terminé',
      icon: Icons.lock_outline,
    );
  }

  // archived (valeur par défaut défensive)
  return (
    tone: StatusPillTone.neutral,
    label: 'Archivé',
    icon: Icons.archive_outlined,
  );
}
