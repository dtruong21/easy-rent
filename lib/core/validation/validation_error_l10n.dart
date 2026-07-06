import 'package:flutter/widgets.dart';

import '../i18n/l10n_extensions.dart';
import 'validation_error.dart';

/// Traduit un [ValidationError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`validation_error.dart`) reste pur. Voir
/// `lib/l10n/l10n_convention.dart` pour le pattern complet.
extension ValidationErrorL10n on ValidationError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ValidationError.required => l10n.validationRequired,
      ValidationError.invalidEmail => l10n.validationInvalidEmail,
    };
  }
}
