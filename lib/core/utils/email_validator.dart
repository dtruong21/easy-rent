/// Validation d'adresse email — logique pure, sans dépendance Flutter.
///
/// Utilisée par [AuthController] et testable unitairement sans mock.
class EmailValidator {
  const EmailValidator._();

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  /// Renvoie [true] si [email] est une adresse valide (format RFC-5322 simplifié).
  static bool isValid(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    return _emailRegex.hasMatch(trimmed);
  }
}
