import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/property_type.dart';

/// Libellé localisé de [PropertyType] (FEAT-043 — pattern « enum métier →
/// mapping l10n en présentation », cf. `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`property_type.dart`) reste un enum nu, sans dépendance à
/// `AppLocalizations`/`BuildContext` (`labelFr` y est conservé pour la
/// sérialisation SQL/tri, mais l'UI doit utiliser [label] désormais).
extension PropertyTypeL10n on PropertyType {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      PropertyType.appartement => l10n.propertiesTypeAppartement,
      PropertyType.maison => l10n.propertiesTypeMaison,
      PropertyType.studio => l10n.propertiesTypeStudio,
      PropertyType.autre => l10n.propertiesTypeAutre,
    };
  }
}
