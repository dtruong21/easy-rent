import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
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
/// Priorité descendante (FEAT-028 ajoute `late` en tête — un impayé est
/// plus urgent qu'une échéance de renouvellement) :
/// 1. `active` ET [isLate] → danger "En retard"
/// 2. `active` ET endDate − today < 60 jours → warning "À renouveler"
/// 3. `active` (par défaut) → success "Actif"
/// 4. `terminated` → neutral "Terminé"
/// 5. `archived` → neutral "Archivé"
///
/// [isLate] doit être calculé en amont par l'appelant (cf.
/// `lease_lateness.dart::isLeaseLate`, qui a besoin de l'historique des
/// paiements du bail — non disponible depuis un [Lease] seul). Défaut
/// `false` pour ne pas casser les appelants qui n'ont pas encore cette info.
///
/// Le paramètre [now] est injectable pour les tests (évite la dépendance
/// à `DateTime.now()` dans les tests unitaires).
///
/// [context] est requis pour la localisation des libellés (FEAT-043) — les
/// appelants sont tous des widgets avec un `BuildContext` disponible.
LeaseStatusPillData leaseStatusPill(
  BuildContext context,
  Lease lease, {
  DateTime? now,
  bool isLate = false,
}) {
  final l10n = context.l10n;
  final today = now ?? DateTime.now();

  if (lease.status == LeaseStatus.active) {
    if (isLate) {
      return (
        tone: StatusPillTone.danger,
        // Réutilise `leasesFilterLate` (valeur FR identique "En retard") —
        // pas de duplication de clé pour un même libellé, cf. convention
        // ARB (`lib/l10n/l10n_convention.dart`, règle 2).
        label: l10n.leasesFilterLate,
        icon: Icons.warning_amber_outlined,
      );
    }

    final end = lease.endDate;
    if (end != null) {
      final daysUntilEnd = end.difference(today).inDays;
      if (daysUntilEnd < 60) {
        return (
          tone: StatusPillTone.warning,
          // Réutilise `leasesFilterRenewable` (valeur FR identique
          // "À renouveler") — idem, pas de duplication de clé.
          label: l10n.leasesFilterRenewable,
          icon: Icons.event_repeat_outlined,
        );
      }
    }
    return (
      tone: StatusPillTone.success,
      label: l10n.leasesStatusActive,
      icon: Icons.check_circle_outline,
    );
  }

  if (lease.status == LeaseStatus.terminated) {
    return (
      tone: StatusPillTone.neutral,
      label: l10n.leasesStatusTerminated,
      icon: Icons.lock_outline,
    );
  }

  // archived (valeur par défaut défensive)
  return (
    tone: StatusPillTone.neutral,
    label: l10n.leasesStatusArchived,
    icon: Icons.archive_outlined,
  );
}
