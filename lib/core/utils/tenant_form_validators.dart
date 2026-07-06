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
/// [validateEmailError] est l'exemple pilote FEAT-043 (i18n) du pattern
/// « validator → enum d'erreur mappé en présentation » — voir
/// `lib/l10n/l10n_convention.dart`. Les autres méthodes de cette classe
/// restent en `String?` FR en dur pour l'instant (extraction complète hors
/// périmètre de la foundation).
class TenantFormValidators {
  const TenantFormValidators._();

  /// Valide le prénom du locataire.
  ///
  /// Retourne [null] si valide, un message d'erreur FR sinon.
  static String? validateFirstName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le prénom est obligatoire';
    }
    return null;
  }

  /// Valide le nom de famille du locataire.
  ///
  /// Retourne [null] si valide, un message d'erreur FR sinon.
  static String? validateLastName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le nom est obligatoire';
    }
    return null;
  }

  /// Valide l'adresse email du locataire.
  ///
  /// Champ obligatoire + format RFC-5322 simplifié via [EmailValidator].
  /// Retourne [null] si valide, un message d'erreur FR sinon.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "L'adresse email est obligatoire";
    }
    if (!EmailValidator.isValid(value)) {
      return 'Adresse email invalide (ex. : jean.dupont@email.com)';
    }
    return null;
  }

  /// Valide l'adresse email du locataire — variante pilote FEAT-043 (i18n).
  ///
  /// Même règle que [validateEmail], mais retourne un [ValidationError]
  /// (indépendant de la locale) au lieu d'un message FR en dur. La couche
  /// présentation traduit via `ValidationErrorL10n.message(context)`.
  static ValidationError? validateEmailError(String? value) {
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
  static String? validatePhone(String? value) {
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
  static String? validateBirthDate(DateTime? value) {
    if (value == null) return null;
    final minDate = DateTime(1900);
    final maxDate = DateTime(
      DateTime.now().year - 18,
      DateTime.now().month,
      DateTime.now().day,
    );
    if (value.isBefore(minDate)) {
      return 'Date de naissance invalide (minimum 1900)';
    }
    if (value.isAfter(maxDate)) {
      return 'Le locataire doit avoir au moins 18 ans';
    }
    return null;
  }

  /// Valide le lieu de naissance (1..100 caractères). Optionnel : null si vide.
  static String? validateBirthPlace(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 100) {
      return 'Lieu de naissance trop long (100 caractères maximum)';
    }
    return null;
  }

  /// Valide la nationalité (1..60 caractères). Optionnel : null si vide.
  static String? validateNationality(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 60) {
      return 'Nationalité trop longue (60 caractères maximum)';
    }
    return null;
  }

  /// Valide la profession (1..100 caractères). Optionnel : null si vide.
  static String? validateProfession(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 100) {
      return 'Profession trop longue (100 caractères maximum)';
    }
    return null;
  }

  /// Valide l'employeur (1..100 caractères). Optionnel : null si vide.
  static String? validateEmployer(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 100) {
      return 'Employeur trop long (100 caractères maximum)';
    }
    return null;
  }

  /// Valide les revenus mensuels nets en centimes (0..10 000 000 000).
  ///
  /// Retourne [null] si null (champ optionnel).
  static String? validateMonthlyIncomeCents(int? value) {
    if (value == null) return null;
    if (value < 0 || value > 10000000000) {
      return 'Revenus invalides';
    }
    return null;
  }

  /// Valide l'adresse précédente (1..300 caractères). Optionnel : null si vide.
  static String? validatePreviousAddress(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 300) {
      return 'Adresse précédente trop longue (300 caractères maximum)';
    }
    return null;
  }

  /// Valide le nom du garant (1..200 caractères). Optionnel : null si vide.
  static String? validateGuarantorName(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 200) {
      return 'Nom du garant trop long (200 caractères maximum)';
    }
    return null;
  }

  /// Valide l'email du garant. Optionnel : null si vide.
  ///
  /// Si renseigné, vérifie le format email RFC-5322 simplifié.
  static String? validateGuarantorEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!EmailValidator.isValid(value)) {
      return 'Email du garant invalide (ex. : garant@email.com)';
    }
    return null;
  }

  /// Valide le téléphone du garant (1..30 caractères). Optionnel : null si vide.
  static String? validateGuarantorPhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length > 30) {
      return 'Téléphone du garant trop long (30 caractères maximum)';
    }
    return null;
  }
}
