import 'package:flutter/material.dart';

import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../domain/tenant_list_item.dart';

/// Résultat du mapping statut locataire → pill.
typedef TenantOccupancyPillData = ({
  StatusPillTone tone,
  String label,
  IconData icon,
});

/// Mappe un [TenantListItem] vers les propriétés d'affichage d'un [StatusPill].
///
/// Logique :
/// - `activeLeaseId != null` → success "Actif"
/// - `activeLeaseId == null` → warning "Sans bail"
///
/// Deux statuts seulement (pas de "Inactif" distinct — granularité historique
/// disponible dans `/tenants/:id`). Décision verrouillée Phase 3.
TenantOccupancyPillData tenantOccupancyPill(TenantListItem item) {
  if (item.activeLeaseId != null) {
    return (
      tone: StatusPillTone.success,
      label: 'Actif',
      icon: Icons.person_outline,
    );
  }

  return (
    tone: StatusPillTone.warning,
    label: 'Sans bail',
    icon: Icons.person_add_outlined,
  );
}
