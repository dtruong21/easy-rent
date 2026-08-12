import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/property_color.dart';

/// Libellé localisé de [PropertyColorKey] (même pattern que
/// `PropertyTypeL10n` — enum nu côté domaine/thème, mapping l10n en
/// présentation, cf. `lib/l10n/l10n_convention.dart`).
extension PropertyColorKeyL10n on PropertyColorKey {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      PropertyColorKey.rouille => l10n.propertiesColorNameRouille,
      PropertyColorKey.bordeaux => l10n.propertiesColorNameBordeaux,
      PropertyColorKey.prune => l10n.propertiesColorNamePrune,
      PropertyColorKey.cobalt => l10n.propertiesColorNameCobalt,
      PropertyColorKey.ardoise => l10n.propertiesColorNameArdoise,
      PropertyColorKey.sauge => l10n.propertiesColorNameSauge,
      PropertyColorKey.moutarde => l10n.propertiesColorNameMoutarde,
      PropertyColorKey.rosePoudre => l10n.propertiesColorNameRosePoudre,
    };
  }
}
