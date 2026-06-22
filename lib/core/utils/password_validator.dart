/// Validation de mot de passe — logique pure, sans dépendance Flutter.
///
/// Politique : 8 caractères min + au moins 1 lettre + au moins 1 chiffre.
/// Alignée sur la config Supabase (password_min_length=8, require_uppercase=false).
class PasswordValidator {
  const PasswordValidator._();

  static const int minLength = 8;

  static final RegExp _letter = RegExp(r'[a-zA-Z]');
  static final RegExp _digit = RegExp(r'\d');

  /// Renvoie [null] si valide, sinon le message d'erreur en français.
  static String? validate(String? value) {
    if (value == null || value.isEmpty) return 'Mot de passe requis';
    if (value.length < minLength) return '8 caractères minimum';
    if (!_letter.hasMatch(value)) return 'Au moins une lettre';
    if (!_digit.hasMatch(value)) return 'Au moins un chiffre';
    return null;
  }
}
