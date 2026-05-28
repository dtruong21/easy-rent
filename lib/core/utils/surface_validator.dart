/// Validation et parsing de la surface en m² — logique pure, sans dépendance Flutter.
///
/// Accepte la saisie française (virgule ou point décimal).
/// Cohérent avec la contrainte SQL `numeric(6,2) CHECK > 0` :
/// - Maximum 6 chiffres entiers + 2 décimales → max 9999.99 (valeur la plus
///   haute avec 4 chiffres entiers valides avec 2 décimales dans numeric(6,2)).
///
/// Testable unitairement sans mock.
class SurfaceValidator {
  const SurfaceValidator._();

  /// Parse et valide une surface saisie en français.
  ///
  /// Retourne [null] si [input] est vide (champ optionnel — envoie NULL en base).
  /// Retourne le [double] si valide.
  /// Lance un [SurfaceValidationException] si invalide.
  static double? parse(String input) {
    final trimmed = input.trim();

    // Champ optionnel — vide = null acceptable.
    if (trimmed.isEmpty) return null;

    // Accepte la virgule française comme séparateur décimal.
    final normalized = trimmed.replaceAll(',', '.');

    final value = double.tryParse(normalized);
    if (value == null) {
      throw const SurfaceValidationException('Surface invalide');
    }

    if (value <= 0) {
      throw const SurfaceValidationException('La surface doit être positive');
    }

    if (value > 9999.99) {
      throw const SurfaceValidationException('Surface maximale 9999,99 m²');
    }

    return value;
  }

  /// Valide une surface et retourne un message d'erreur en français, ou [null] si OK.
  ///
  /// Adapté pour les [FormField.validator] Flutter.
  static String? validate(String? input) {
    try {
      parse(input ?? '');
      return null;
    } on SurfaceValidationException catch (e) {
      return e.message;
    }
  }
}

/// Exception levée par [SurfaceValidator.parse] en cas de valeur invalide.
class SurfaceValidationException implements Exception {
  const SurfaceValidationException(this.message);

  final String message;

  @override
  String toString() => 'SurfaceValidationException: $message';
}
