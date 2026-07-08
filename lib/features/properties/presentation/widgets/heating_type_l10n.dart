import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/heating_type.dart';

/// Libellé localisé de [HeatingType] (FEAT-043 — pattern « enum métier →
/// mapping l10n en présentation », cf. `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`heating_type.dart`) reste un enum nu, sans dépendance à
/// `AppLocalizations`/`BuildContext` (`labelFr` y est conservé pour la
/// sérialisation SQL, mais l'UI doit utiliser [label] désormais).
extension HeatingTypeL10n on HeatingType {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      HeatingType.electric => l10n.propertiesHeatingElectric,
      HeatingType.gas => l10n.propertiesHeatingGas,
      HeatingType.collective => l10n.propertiesHeatingCollective,
      HeatingType.fuel => l10n.propertiesHeatingFuel,
      HeatingType.wood => l10n.propertiesHeatingWood,
      HeatingType.heatPump => l10n.propertiesHeatingHeatPump,
      HeatingType.other => l10n.propertiesHeatingOther,
    };
  }
}
