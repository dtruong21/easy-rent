import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/property_filter.dart';

/// Libellé localisé de [PropertyFilter] (FEAT-043 — pattern « enum métier →
/// mapping l10n en présentation », cf. `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`property_filter.dart`) reste un enum nu, sans dépendance à
/// `AppLocalizations`/`BuildContext` (`labelFr` y est conservé mais l'UI
/// doit utiliser [label] désormais).
extension PropertyFilterL10n on PropertyFilter {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      PropertyFilter.all => l10n.propertiesFilterAll,
      PropertyFilter.occupied => l10n.propertiesFilterOccupied,
      PropertyFilter.vacant => l10n.propertiesFilterVacant,
    };
  }
}
