import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/delete_account_error.dart';

/// Traduit un [DeleteAccountError] en message localisé (FEAT-045 / i18n
/// FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le domaine
/// (`delete_account_error.dart`) reste pur. Même pattern que `AuthErrorL10n`
/// (`lib/features/auth/presentation/auth_error_l10n.dart`).
///
/// Consommé par `profile/presentation/delete_account_page.dart` (flux in-app)
/// et `auth/presentation/delete_account_request_page.dart` (page publique).
extension DeleteAccountErrorL10n on DeleteAccountError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      // Réutilise la clé existante (même texte que la ré-auth par mot de passe
      // du changement de mot de passe), plutôt que d'en dupliquer une.
      DeleteAccountError.wrongPassword =>
        l10n.authErrorCurrentPasswordIncorrect,
      DeleteAccountError.userMismatch => l10n.deleteAccountErrorUserMismatch,
      DeleteAccountError.reauthCancelled =>
        l10n.deleteAccountErrorReauthCancelled,
      DeleteAccountError.popupBlocked => l10n.deleteAccountErrorPopupBlocked,
      DeleteAccountError.network => l10n.deleteAccountErrorNetwork,
      DeleteAccountError.sessionTooOld => l10n.deleteAccountErrorSessionTooOld,
      DeleteAccountError.connectionFailed =>
        l10n.deleteAccountErrorConnectionFailed,
      DeleteAccountError.unknown => l10n.deleteAccountErrorGeneric,
    };
  }
}
