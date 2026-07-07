import '../validation/validation_error.dart';
import 'email_validator.dart';

/// Validateurs du formulaire locataire — logique pure, sans dépendance Flutter.
///
/// Testables unitairement sans mock. Même pattern que les validateurs de `properties`
/// (volontairement séparés tant qu'on n'a pas 3+ usages d'un validateur partagé).
///
/// Note : [validatePhone] retourne toujours `null` en V1 (string libre acceptée).
/// Le hook est en place pour une évolution future (regex internationale ou package
/// `phone_validator` en P1).
///
/// FEAT-043 (i18n) : retourne un [ValidationError] (pur, sans `BuildContext`)
/// au lieu d'un message FR en dur — voir `lib/l10n/l10n_convention.dart`.
class TenantFormValidators {
  const TenantFormValidators._();

  /// Valide le prénom du locataire.
  ///
  /// Retourne [null] si valide, une erreur sinon.
  static ValidationError? validateFirstName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.firstNameRequired;
    }
    return null;
  }

  /// Valide le nom de famille du locataire.
  ///
  /// Retourne [null] si valide, une erreur sinon.
  static ValidationError? validateLastName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.lastNameRequired;
    }
    return null;
  }

  /// Valide l'adresse email du locataire.
  ///
  /// Champ obligatoire + format RFC-5322 simplifié via [EmailValidator].
  /// Retourne [null] si valide, une erreur sinon.
  static ValidationError? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.required;
    }
    if (!EmailValidator.isValid(value)) {
      return ValidationError.invalidEmail;
    }
    return null;
  }

  /// Valide le numéro de téléphone du locataire.
  ///
  /// V1 : string libre acceptée — retourne toujours [null].
  /// Champ optionnel, aucune regex appliquée.
  ///
  /// TODO(P1) : ajouter une validation internationale si le besoin est confirmé.
  static ValidationError? validatePhone(String? value) {
    // Pas de validation en V1 — string libre.
    return null;
  }

  // ---------------------------------------------------------------------------
  // Champs FEAT-014 Phase 2 — tous optionnels (retournent null si vide)
  // ---------------------------------------------------------------------------

  /// Valide la date de naissance.
  ///
  /// Retourne [null] si null (champ optionnel).
  /// Sinon vérifie : >= 1900-01-01 et <= aujourd'hui - 18 ans.
  static ValidationError? validateBirthDate(DateTime? value) {
    if (value == null) return null;
    final minDate = DateTime(1900);
    final maxDate = DateTime(
      DateTime.now().year - 18,
      DateTime.now().month,
      DateTime.now().day,
    );
    if (value.isBefore(minDate)) {
      return ValidationError.birthDateTooEarly;
    }
    if (value.isAfter(maxDate)) {
      return ValidationError.tenantMustBeAdult;
    }
    return null;
  }

  /// Valide le lieu de naissance (1..100 caractères). Optionnel : null si vide.
  static ValidationError? validateBirthPlace(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 100) {
      return ValidationError.birthPlaceTooLong;
    }
    return null;
  }

  /// Valide la nationalité (1..60 caractères). Optionnel : null si vide.
  static ValidationError? validateNationality(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 60) {
      return ValidationError.nationalityTooLong;
    }
    return null;
  }

  /// Valide la profession (1..100 caractères). Optionnel : null si vide.
  static ValidationError? validateProfession(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 100) {
      return ValidationError.professionTooLong;
    }
    return null;
  }

  /// Valide l'employeur (1..100 caractères). Optionnel : null si vide.
  static ValidationError? validateEmployer(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 100) {
      return ValidationError.employerTooLong;
    }
    return null;
  }

  /// Valide les revenus mensuels nets en centimes (0..10 000 000 000).
  ///
  /// Retourne [null] si null (champ optionnel).
  static ValidationError? validateMonthlyIncomeCents(int? value) {
    if (value == null) return null;
    if (value < 0 || value > 10000000000) {
      return ValidationError.monthlyIncomeInvalid;
    }
    return null;
  }

  /// Valide l'adresse précédente (1..300 caractères). Optionnel : null si vide.
  static ValidationError? validatePreviousAddress(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 300) {
      return ValidationError.previousAddressTooLong;
    }
    return null;
  }

  /// Valide le nom du garant (1..200 caractères). Optionnel : null si vide.
  static ValidationError? validateGuarantorName(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 200) {
      return ValidationError.guarantorNameTooLong;
    }
    return null;
  }

  /// Valide l'email du garant. Optionnel : null si vide.
  ///
  /// Si renseigné, vérifie le format email RFC-5322 simplifié.
  static ValidationError? validateGuarantorEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!EmailValidator.isValid(value)) {
      return ValidationError.invalidGuarantorEmail;
    }
    return null;
  }

  /// Valide le téléphone du garant (1..30 caractères). Optionnel : null si vide.
  static ValidationError? validateGuarantorPhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 30) {
      return ValidationError.guarantorPhoneTooLong;
    }
    return null;
  }
}
