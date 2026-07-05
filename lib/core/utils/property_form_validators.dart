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

  // ---------------------------------------------------------------------------
  // FEAT-017 — Validateurs Financement & acquisition
  // ---------------------------------------------------------------------------

  /// Valide le prix d'achat (> 0 et < 1G€ = 100_000_000_000 centimes).
  /// Champ optionnel : retourne [null] si vide.
  static String? validatePurchasePrice(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim().replaceAll(' ', ''));
    if (n == null || n <= 0) {
      return "Le prix d'achat doit être un nombre entier positif";
    }
    // Limite à 1 milliard d'euros (100 000 000 000 centimes).
    if (n > 100000000000) {
      return "Le prix d'achat ne peut pas dépasser 1 milliard d'euros";
    }
    return null;
  }

  /// Valide les frais de notaire (>= 0). Champ optionnel : retourne [null] si vide.
  static String? validateNotaryFees(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim().replaceAll(' ', ''));
    if (n == null || n < 0) {
      return 'Les frais de notaire doivent être un nombre positif ou nul';
    }
    return null;
  }

  /// Valide un montant annuel en euros (>= 0). Champ optionnel : retourne [null] si vide.
  static String? validateAnnualAmount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim().replaceAll(' ', ''));
    if (n == null || n < 0) {
      return 'Le montant doit être un nombre positif ou nul';
    }
    return null;
  }

  /// Valide le taux nominal du prêt (0..30 % = 0..3000 bps).
  /// Saisie en pourcentage (ex. "3.5" pour 3,5 %).
  /// Champ optionnel : retourne [null] si vide.
  static String? validateLoanRate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final d = double.tryParse(value.trim().replaceAll(',', '.'));
    if (d == null || d < 0 || d > 30) {
      return 'Taux invalide (0 % à 30 %)';
    }
    return null;
  }

  /// Valide la durée du prêt en mois (12..360).
  /// Champ optionnel : retourne [null] si vide.
  static String? validateLoanDuration(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 12 || n > 360) {
      return 'Durée invalide (12 à 360 mois)';
    }
    return null;
  }

  /// Valide le taux d'assurance emprunteur (0..2 % = 0..200 bps).
  /// Saisie en pourcentage (ex. "0.30").
  /// Champ optionnel : retourne [null] si vide.
  static String? validateInsuranceRate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final d = double.tryParse(value.trim().replaceAll(',', '.'));
    if (d == null || d < 0 || d > 2) {
      return "Taux d'assurance invalide (0 % à 2 %)";
    }
    return null;
  }

  /// Valide le capital emprunté (> 0). Champ optionnel : retourne [null] si vide.
  static String? validateLoanPrincipal(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim().replaceAll(' ', ''));
    if (n == null || n <= 0) {
      return 'Le capital emprunté doit être un nombre entier positif';
    }
    return null;
  }
}
