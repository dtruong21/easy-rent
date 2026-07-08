/// Erreurs d'authentification, indépendantes de la locale d'affichage
/// (FEAT-043 i18n).
///
/// **Périmètre** : couvre à la fois les codes Firebase Auth natifs /
/// [GoogleAuthErrorCode] / [AppleAuthErrorCode] mappés par
/// `AuthErrorMapper.fromException` (`lib/features/auth/data/
/// auth_error_mapper.dart`), les gardes de validation des contrôleurs
/// `application/` (`LoginController`, `SignupController`,
/// `ForgotPasswordController`, `ResetPasswordController`,
/// `ChangePasswordController`) et `PasswordValidator`
/// (`lib/core/utils/password_validator.dart`). Un seul enum pour ces trois
/// sources car elles alimentent toutes le même champ
/// `XxxState.error(message: String)` (freezed).
///
/// **Contrainte technique** : identique au pattern `TenantSubmitError`
/// (`lib/features/tenants/domain/tenant_submit_error.dart`) —
/// régénérer `LoginPageState`/`SignupPageState`/`ForgotPasswordState`/
/// `ResetPasswordState`/`ChangePasswordState` avec un champ enum typé est
/// hors périmètre (nécessite de relancer `build_runner`, non disponible
/// dans cet environnement). Pattern retenu : les contrôleurs stockent le
/// **nom** de cet enum (`AuthError.xxx.name`, une clé technique stable,
/// jamais un message FR) dans `XxxState.error.message` ; la couche
/// présentation (`AuthErrorL10n`,
/// `lib/features/auth/presentation/auth_error_l10n.dart`) le reconvertit
/// pour l'affichage — widgets consommateurs : pages/formulaires `auth/`
/// ET `profile/presentation/widgets/profile_change_password_form.dart`
/// (même contrôleur `ChangePasswordController`, coordination inter-module).
///
/// Mêmes garanties que `ValidationError`
/// (`lib/core/validation/validation_error.dart`) : aucune dépendance à
/// `BuildContext`/`AppLocalizations` ici.
enum AuthError {
  // ---------------------------------------------------------------------
  // AuthErrorMapper — codes Firebase Auth natifs
  // ---------------------------------------------------------------------

  /// `invalid-credential` / `invalid-email` / `wrong-password` /
  /// `user-not-found` — regroupés par anti-énumération OWASP (ne jamais
  /// préciser lequel des deux, email ou mot de passe, est erroné).
  invalidCredentials,

  /// `user-disabled`.
  userDisabled,

  /// `email-already-in-use`.
  emailAlreadyInUse,

  /// `weak-password` — rejet Firebase natif (6 caractères min côté
  /// Firebase), distinct des règles `PasswordValidator` appliquées côté
  /// app avant l'appel réseau (8 caractères + lettre + chiffre).
  weakPassword,

  /// `too-many-requests`.
  tooManyRequests,

  /// `requires-recent-login` (FEAT-025 : changement de mot de passe
  /// in-app exige une session « récente »).
  requiresRecentLogin,

  /// `expired-action-code` / `invalid-action-code`.
  expiredActionCode,

  /// `network-request-failed`.
  networkRequestFailed,

  /// `operation-not-allowed`.
  operationNotAllowed,

  // ---------------------------------------------------------------------
  // AuthErrorMapper — codes Google (natifs Firebase + `baillan/google-*`)
  // ---------------------------------------------------------------------

  /// `popup-closed-by-user` (natif) / [GoogleAuthErrorCode.popupClosed]
  /// (synthétique Baillan, même texte).
  googlePopupClosed,

  /// `popup-blocked` (natif) / [GoogleAuthErrorCode.popupBlocked]
  /// (synthétique Baillan, même texte).
  googlePopupBlocked,

  /// `account-exists-with-different-credential` — partagé Google et Apple
  /// (le message ne mentionne pas le provider).
  accountExistsWithDifferentCredential,

  /// `cancelled-popup-request`.
  googlePopupCancelledRequest,

  /// `web-storage-unsupported`.
  webStorageUnsupported,

  /// [GoogleAuthErrorCode.newUserOnLogin] — tentative de connexion Google
  /// sans compte Baillan associé.
  googleNewUserOnLogin,

  // ---------------------------------------------------------------------
  // AuthErrorMapper — codes Apple (natif Firebase + `baillan/apple-*`)
  // ---------------------------------------------------------------------

  /// `user-cancelled` (natif) / [AppleAuthErrorCode.popupClosed]
  /// (synthétique Baillan, même texte).
  applePopupClosed,

  /// [AppleAuthErrorCode.newUserOnLogin] — tentative de connexion Apple
  /// sans compte Baillan associé.
  appleNewUserOnLogin,

  /// [AppleAuthErrorCode.popupBlocked].
  applePopupBlocked,

  // ---------------------------------------------------------------------
  // Partagé Google + Apple + garde locale signup (consentement RGPD)
  // ---------------------------------------------------------------------

  /// [GoogleAuthErrorCode.consentDeclined] / [AppleAuthErrorCode.consentDeclined]
  /// / garde locale `SignupController` (case RGPD non cochée au moment du
  /// clic, avant tout appel repository). Message identique à la checkbox
  /// de consentement du formulaire signup (`SignupForm._ConsentCheckbox`)
  /// — voir `AuthErrorL10n.message`, qui route ce cas vers la clé ARB déjà
  /// existante `authConsentRequiredError` plutôt que d'en dupliquer une
  /// nouvelle (`l10n_convention.dart` §2 : grep les clés existantes avant
  /// d'en ajouter).
  consentRequired,

  // ---------------------------------------------------------------------
  // Gardes locales des contrôleurs application/
  // ---------------------------------------------------------------------

  /// Email au format invalide (`LoginController.signIn`,
  /// `SignupController.signUp`, `ForgotPasswordController.sendResetEmail`).
  /// Message identique à `ValidationError.invalidEmail`
  /// (clé ARB `validationInvalidEmail`) — réutilisé tel quel plutôt que
  /// dupliqué.
  invalidEmailFormat,

  /// Mot de passe laissé vide (`LoginController.signIn` — hors du flow
  /// `PasswordValidator`, qui n'est appelé qu'au signup/reset/change).
  /// Même texte que `PasswordValidator` sur valeur vide (voir
  /// [passwordTooShort] et suivants).
  passwordRequired,

  /// Email non vérifié après connexion réussie (FEAT-021,
  /// `LoginController.signIn`) — un email de vérification vient d'être
  /// renvoyé automatiquement avant la déconnexion forcée.
  emailNotVerified,

  /// Nom complet laissé vide (`SignupController.signUp`).
  fullNameRequired,

  /// Confirmation de mot de passe différente du nouveau mot de passe
  /// (`SignupController`, `ResetPasswordController`,
  /// `ChangePasswordController`).
  passwordsMismatch,

  /// `oobCode` de réinitialisation manquant dans l'URL
  /// (`ResetPasswordController.confirmReset`).
  missingResetCode,

  /// Nouveau mot de passe identique à l'actuel
  /// (`ChangePasswordController.submit`).
  newPasswordSameAsCurrent,

  /// Mot de passe actuel incorrect lors de la ré-authentification
  /// (`ChangePasswordController._mapError`) — mapping dédié : le libellé
  /// générique [invalidCredentials] mentionne « Email », qui n'a pas de
  /// sens ici (utilisateur déjà connecté, ne saisit qu'un mot de passe).
  currentPasswordIncorrect,

  // ---------------------------------------------------------------------
  // PasswordValidator (lib/core/utils/password_validator.dart)
  // ---------------------------------------------------------------------

  /// Moins de 8 caractères (`PasswordValidator.minLength`).
  passwordTooShort,

  /// Aucune lettre (a-z/A-Z) dans le mot de passe.
  passwordMissingLetter,

  /// Aucun chiffre dans le mot de passe.
  passwordMissingDigit,

  // ---------------------------------------------------------------------
  // Générique
  // ---------------------------------------------------------------------

  /// Erreur inattendue (catch-all des contrôleurs + cas par défaut du
  /// mapper). Message identique à `commonErrorGeneric`, réutilisé (voir
  /// `AuthErrorL10n.message`) plutôt que dupliqué sous un nouveau libellé.
  unknown;

  /// Reconstruit l'enum depuis son [name] stocké dans
  /// `XxxState.error.message` — retourne [unknown] si absent/invalide (ne
  /// doit jamais arriver en pratique, filet de sécurité défensif).
  static AuthError fromCode(String code) {
    return AuthError.values.firstWhere(
      (e) => e.name == code,
      orElse: () => AuthError.unknown,
    );
  }
}
