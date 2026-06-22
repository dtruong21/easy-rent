/// Validateurs du formulaire bien immobilier — logique pure, sans dépendance Flutter.
///
/// Testables unitairement sans mock. Pattern identique à [EmailValidator].
class PropertyFormValidators {
  const PropertyFormValidators._();

  /// Valide le nom du bien.
  ///
  /// Retourne [null] si valide, un message d'erreur FR sinon.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le nom du bien est obligatoire';
    }
    return null;
  }

  /// Valide l'adresse du bien.
  ///
  /// Retourne [null] si valide, un message d'erreur FR sinon.
  static String? validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "L'adresse est obligatoire";
    }
    return null;
  }

  /// Valide le code postal (5 chiffres). Champ optionnel : retourne [null] si vide.
  static String? validatePostalCode(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (!RegExp(r'^\d{5}$').hasMatch(trimmed)) {
      return 'Code postal invalide (5 chiffres requis, ex : 75001)';
    }
    return null;
  }

  /// Valide le nombre de pièces (1..50). Champ optionnel : retourne [null] si vide.
  static String? validateRooms(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 1 || n > 50) {
      return 'Nombre de pièces invalide (1 à 50)';
    }
    return null;
  }

  /// Valide le nombre de chambres (0..50). Champ optionnel : retourne [null] si vide.
  static String? validateBedrooms(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 0 || n > 50) {
      return 'Nombre de chambres invalide (0 à 50)';
    }
    return null;
  }

  /// Valide l'étage (-5..200). Champ optionnel : retourne [null] si vide.
  ///
  /// 0 = RDC, négatif autorisé pour sous-sol.
  static String? validateFloor(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < -5 || n > 200) {
      return 'Étage invalide (-5 à 200, 0 = RDC)';
    }
    return null;
  }

  /// Valide l'année de construction (1700..(now+1)). Champ optionnel : retourne [null] si vide.
  static String? validateConstructionYear(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    final maxYear = DateTime.now().year + 1;
    if (n == null || n < 1700 || n > maxYear) {
      return 'Année invalide (1700 à $maxYear)';
    }
    return null;
  }

  /// Valide la lettre DPE (A..G). Champ optionnel : retourne [null] si vide.
  static String? validateDpeLetter(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim().toUpperCase();
    if (!RegExp(r'^[A-G]$').hasMatch(trimmed)) {
      return 'Classe DPE invalide (A à G)';
    }
    return null;
  }

  /// Valide la valeur DPE (1..1999 kWh/m²/an). Champ optionnel : retourne [null] si vide.
  static String? validateDpeValue(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 1 || n > 1999) {
      return 'Valeur DPE invalide (1 à 1999 kWh/m²/an)';
    }
    return null;
  }

  /// Valide la lettre GES (A..G). Champ optionnel : retourne [null] si vide.
  static String? validateGesLetter(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim().toUpperCase();
    if (!RegExp(r'^[A-G]$').hasMatch(trimmed)) {
      return 'Classe GES invalide (A à G)';
    }
    return null;
  }
}
