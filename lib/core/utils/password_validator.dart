import '../../features/auth/domain/auth_error.dart';

/// Validation de mot de passe — logique pure, sans dépendance Flutter.
///
/// Politique : 8 caractères min + au moins 1 lettre + au moins 1 chiffre.
/// Alignée sur la config Firebase Auth côté projet (le rejet natif
/// `weak-password` de Firebase n'exige que 6 caractères — cette règle app
/// est plus stricte).
///
/// **FEAT-043 (i18n)** : [validate] retourne un [AuthError]? (au lieu d'un
/// `String?` FR en dur), même pattern que les validateurs
/// `ValidationError` (`lib/core/validation/validation_error.dart`) — sauf
/// que ses cas vivent dans l'enum partagé [AuthError] (pas
/// `ValidationError`), car ses seuls appelants sont des contrôleurs
/// `application/` du module `auth` (`SignupController`,
/// `ResetPasswordController`, `ChangePasswordController`) qui stockent déjà
/// `AuthError.xxx.name` dans leur état d'erreur — voir [AuthError] pour le
/// détail du pipeline. Aucun widget n'utilise [validate] comme
/// `FormField.validator` (seulement des comparaisons `== null` pour
/// activer/désactiver un bouton), donc ce changement de type n'impacte pas
/// les widgets consommateurs.
class PasswordValidator {
  const PasswordValidator._();

  static const int minLength = 8;

  static final RegExp _letter = RegExp(r'[a-zA-Z]');
  static final RegExp _digit = RegExp(r'\d');

  /// Renvoie `null` si valide, sinon l'[AuthError] correspondant.
  static AuthError? validate(String? value) {
    if (value == null || value.isEmpty) return AuthError.passwordRequired;
    if (value.length < minLength) return AuthError.passwordTooShort;
    if (!_letter.hasMatch(value)) return AuthError.passwordMissingLetter;
    if (!_digit.hasMatch(value)) return AuthError.passwordMissingDigit;
    return null;
  }
}
