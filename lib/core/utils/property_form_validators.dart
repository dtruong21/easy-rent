import '../validation/validation_error.dart';

/// Validateurs du formulaire bien immobilier — logique pure, sans dépendance Flutter.
///
/// Testables unitairement sans mock. Pattern identique à [EmailValidator].
///
/// FEAT-043 (i18n) : retourne un [ValidationError] (pur, sans `BuildContext`)
/// au lieu d'un message FR en dur — voir `lib/l10n/l10n_convention.dart`.
class PropertyFormValidators {
  const PropertyFormValidators._();

  /// Année maximale acceptée pour la construction (année courante + 1).
  ///
  /// Source unique partagée par [validateConstructionYear] (borne de la
  /// validation) et `ValidationErrorL10n.message` (paramètre `{maxYear}` du
  /// message localisé) — évite de dupliquer `DateTime.now().year + 1`.
  static int get maxConstructionYear => DateTime.now().year + 1;

  /// Valide le nom du bien.
  ///
  /// Retourne [null] si valide, une erreur sinon.
  static ValidationError? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.propertyNameRequired;
    }
    return null;
  }

  /// Valide l'adresse du bien.
  ///
  /// Retourne [null] si valide, une erreur sinon.
  static ValidationError? validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.propertyAddressRequired;
    }
    return null;
  }

  /// Valide le code postal (5 chiffres). Champ optionnel : retourne [null] si vide.
  static ValidationError? validatePostalCode(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (!RegExp(r'^\d{5}$').hasMatch(trimmed)) {
      return ValidationError.postalCodeInvalid;
    }
    return null;
  }

  /// Valide le nombre de pièces (1..50). Champ optionnel : retourne [null] si vide.
  static ValidationError? validateRooms(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 1 || n > 50) {
      return ValidationError.roomsInvalid;
    }
    return null;
  }

  /// Valide le nombre de chambres (0..50). Champ optionnel : retourne [null] si vide.
  static ValidationError? validateBedrooms(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 0 || n > 50) {
      return ValidationError.bedroomsInvalid;
    }
    return null;
  }

  /// Valide l'étage (-5..200). Champ optionnel : retourne [null] si vide.
  ///
  /// 0 = RDC, négatif autorisé pour sous-sol.
  static ValidationError? validateFloor(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < -5 || n > 200) {
      return ValidationError.floorInvalid;
    }
    return null;
  }

  /// Valide l'année de construction (1700..(now+1)). Champ optionnel : retourne [null] si vide.
  static ValidationError? validateConstructionYear(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 1700 || n > maxConstructionYear) {
      return ValidationError.constructionYearInvalid;
    }
    return null;
  }

  /// Valide la lettre DPE (A..G). Champ optionnel : retourne [null] si vide.
  static ValidationError? validateDpeLetter(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim().toUpperCase();
    if (!RegExp(r'^[A-G]$').hasMatch(trimmed)) {
      return ValidationError.dpeLetterInvalid;
    }
    return null;
  }

  /// Valide la valeur DPE (1..1999 kWh/m²/an). Champ optionnel : retourne [null] si vide.
  static ValidationError? validateDpeValue(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 1 || n > 1999) {
      return ValidationError.dpeValueInvalid;
    }
    return null;
  }

  /// Valide la lettre GES (A..G). Champ optionnel : retourne [null] si vide.
  static ValidationError? validateGesLetter(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim().toUpperCase();
    if (!RegExp(r'^[A-G]$').hasMatch(trimmed)) {
      return ValidationError.gesLetterInvalid;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // FEAT-017 — Validateurs Financement & acquisition
  // ---------------------------------------------------------------------------

  /// Valide le prix d'achat (> 0 et < 1G€ = 100_000_000_000 centimes).
  /// Champ optionnel : retourne [null] si vide.
  static ValidationError? validatePurchasePrice(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim().replaceAll(' ', ''));
    if (n == null || n <= 0) {
      return ValidationError.purchasePriceInvalid;
    }
    // Limite à 1 milliard d'euros (100 000 000 000 centimes).
    if (n > 100000000000) {
      return ValidationError.purchasePriceTooHigh;
    }
    return null;
  }

  /// Valide les frais de notaire (>= 0). Champ optionnel : retourne [null] si vide.
  static ValidationError? validateNotaryFees(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim().replaceAll(' ', ''));
    if (n == null || n < 0) {
      return ValidationError.notaryFeesInvalid;
    }
    return null;
  }

  /// Valide un montant annuel en euros (>= 0). Champ optionnel : retourne [null] si vide.
  static ValidationError? validateAnnualAmount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim().replaceAll(' ', ''));
    if (n == null || n < 0) {
      return ValidationError.annualAmountInvalid;
    }
    return null;
  }

  /// Valide le taux nominal du prêt (0..30 % = 0..3000 bps).
  /// Saisie en pourcentage (ex. "3.5" pour 3,5 %).
  /// Champ optionnel : retourne [null] si vide.
  static ValidationError? validateLoanRate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final d = double.tryParse(value.trim().replaceAll(',', '.'));
    if (d == null || d < 0 || d > 30) {
      return ValidationError.loanRateInvalid;
    }
    return null;
  }

  /// Valide la durée du prêt en mois (12..360).
  /// Champ optionnel : retourne [null] si vide.
  static ValidationError? validateLoanDuration(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < 12 || n > 360) {
      return ValidationError.loanDurationInvalid;
    }
    return null;
  }

  /// Valide le taux d'assurance emprunteur (0..2 % = 0..200 bps).
  /// Saisie en pourcentage (ex. "0.30").
  /// Champ optionnel : retourne [null] si vide.
  static ValidationError? validateInsuranceRate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final d = double.tryParse(value.trim().replaceAll(',', '.'));
    if (d == null || d < 0 || d > 2) {
      return ValidationError.insuranceRateInvalid;
    }
    return null;
  }

  /// Valide le capital emprunté (> 0). Champ optionnel : retourne [null] si vide.
  static ValidationError? validateLoanPrincipal(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = int.tryParse(value.trim().replaceAll(' ', ''));
    if (n == null || n <= 0) {
      return ValidationError.loanPrincipalInvalid;
    }
    return null;
  }
}
