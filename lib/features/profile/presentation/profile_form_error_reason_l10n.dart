import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/profile_form_state.dart';

/// Traduit un [ProfileFormErrorReason] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) —
/// [ProfileFormController] (application) reste pur. Voir
/// `lib/l10n/l10n_convention.dart` pour le pattern complet (identique à
/// `ValidationErrorL10n`).
extension ProfileFormErrorReasonL10n on ProfileFormErrorReason {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ProfileFormErrorReason.saveFailed => l10n.profileDetailsSaveErrorMessage,
      ProfileFormErrorReason.profileNotFound =>
        l10n.profileDetailsNotFoundErrorMessage,
      ProfileFormErrorReason.unexpected =>
        l10n.profileDetailsUnexpectedErrorMessage,
    };
  }
}
