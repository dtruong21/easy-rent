import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../domain/property_list_item.dart';

/// Résultat du mapping occupation bien → pill.
typedef PropertyOccupancyPillData = ({
  StatusPillTone tone,
  String label,
  IconData icon,
});

/// Mappe un [PropertyListItem] vers les propriétés d'affichage d'un [StatusPill].
///
/// Logique :
/// - `activeLeaseId != null` → success "Loué"
/// - `activeLeaseId == null` → warning "Vacant"
///
/// Note : l'état "Archivé" est théoriquement inaccessible car la RLS
/// `properties_select_own` filtre `deleted_at IS NULL` — les biens archivés
/// ne sont jamais renvoyés par l'API. Prévu Phase 3 si le modèle [Property]
/// expose `deletedAt`.
PropertyOccupancyPillData propertyOccupancyPill(
  PropertyListItem item,
  BuildContext context,
) {
  final l10n = context.l10n;
  if (item.activeLeaseId != null) {
    return (
      tone: StatusPillTone.success,
      label: l10n.propertiesStatusOccupied,
      icon: Icons.home_filled,
    );
  }

  return (
    tone: StatusPillTone.warning,
    label: l10n.propertiesStatusVacant,
    icon: Icons.home_work_outlined,
  );
}
