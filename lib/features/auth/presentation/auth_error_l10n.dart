import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/auth_error.dart';

/// Traduit un [AuthError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`auth_error.dart`) reste pur. Même pattern que
/// `TenantSubmitErrorL10n`
/// (`lib/features/tenants/presentation/tenant_submit_error_l10n.dart`).
///
/// Consommé par les widgets `auth/presentation/**` ET
/// `profile/presentation/widgets/profile_change_password_form.dart`
/// (partage `ChangePasswordController`/`ChangePasswordState`, module
/// `profile`) — coordination inter-module explicite (voir doc [AuthError]).
extension AuthErrorL10n on AuthError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      AuthError.invalidCredentials => l10n.authErrorInvalidCredentials,
      AuthError.userDisabled => l10n.authErrorUserDisabled,
      AuthError.emailAlreadyInUse => l10n.authErrorEmailAlreadyInUse,
      AuthError.weakPassword => l10n.authErrorWeakPassword,
      AuthError.tooManyRequests => l10n.authErrorTooManyRequests,
      AuthError.requiresRecentLogin => l10n.authErrorRequiresRecentLogin,
      AuthError.expiredActionCode => l10n.authErrorExpiredActionCode,
      AuthError.networkRequestFailed => l10n.authErrorNetworkRequestFailed,
      AuthError.operationNotAllowed => l10n.authErrorOperationNotAllowed,
      AuthError.googlePopupClosed => l10n.authErrorGooglePopupClosed,
      AuthError.googlePopupBlocked => l10n.authErrorGooglePopupBlocked,
      AuthError.accountExistsWithDifferentCredential =>
        l10n.authErrorAccountExistsDifferentCredential,
      AuthError.googlePopupCancelledRequest =>
        l10n.authErrorGooglePopupCancelledRequest,
      AuthError.webStorageUnsupported => l10n.authErrorWebStorageUnsupported,
      AuthError.googleNewUserOnLogin => l10n.authErrorGoogleNewUserOnLogin,
      AuthError.applePopupClosed => l10n.authErrorApplePopupClosed,
      AuthError.appleNewUserOnLogin => l10n.authErrorAppleNewUserOnLogin,
      AuthError.applePopupBlocked => l10n.authErrorApplePopupBlocked,
      // Réutilise la clé existante de la checkbox de consentement RGPD
      // (`SignupForm._ConsentCheckbox`) plutôt que d'en dupliquer une.
      AuthError.consentRequired => l10n.authConsentRequiredError,
      // Réutilise la clé existante des validateurs de formulaire (même
      // texte que `ValidationError.invalidEmail`).
      AuthError.invalidEmailFormat => l10n.validationInvalidEmail,
      AuthError.passwordRequired => l10n.authErrorPasswordRequired,
      AuthError.emailNotVerified => l10n.authErrorEmailNotVerified,
      AuthError.fullNameRequired => l10n.authErrorFullNameRequired,
      AuthError.passwordsMismatch => l10n.authErrorPasswordsMismatch,
      AuthError.missingResetCode => l10n.authErrorMissingResetCode,
      AuthError.newPasswordSameAsCurrent =>
        l10n.authErrorNewPasswordSameAsCurrent,
      AuthError.currentPasswordIncorrect =>
        l10n.authErrorCurrentPasswordIncorrect,
      AuthError.passwordTooShort => l10n.authErrorPasswordTooShort,
      AuthError.passwordMissingLetter => l10n.authErrorPasswordMissingLetter,
      AuthError.passwordMissingDigit => l10n.authErrorPasswordMissingDigit,
      // Réutilise le libellé générique transverse plutôt que d'en dupliquer
      // un sous le préfixe `auth*`.
      AuthError.unknown => l10n.commonErrorGeneric,
    };
  }
}
