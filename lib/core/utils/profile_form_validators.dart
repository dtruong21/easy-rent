import '../validation/validation_error.dart';

/// Validateurs du formulaire profil bailleur — logique pure, sans dépendance
/// Flutter.
///
/// Testables unitairement sans mock. Pattern strictement aligné sur
/// [TenantFormValidators] et [PaymentFormValidators].
///
/// Conformité légale :
/// - [validateFullName] et [validateAddress] sont obligatoires pour générer
///   des quittances conformes à la loi 1989 art. 21.
/// - [validatePhone] est facultatif — format libre (FR ou international
///   acceptés).
///
/// FEAT-043 (i18n) : retourne un [ValidationError] (pur, sans `BuildContext`)
/// au lieu d'un message FR en dur — voir `lib/l10n/l10n_convention.dart`.
class ProfileFormValidators {
  const ProfileFormValidators._();

  /// Valide le nom complet du bailleur.
  ///
  /// Obligatoire, longueur 2..200.
  /// Retourne [null] si valide, une erreur sinon.
  static ValidationError? validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.fullNameRequired;
    }
    if (value.trim().length < 2) {
      return ValidationError.fullNameTooShort;
    }
    if (value.trim().length > 200) {
      return ValidationError.fullNameTooLong;
    }
    return null;
  }

  /// Valide l'adresse postale du bailleur.
  ///
  /// Obligatoire, longueur 5..500. Format libre (multi-ligne accepté).
  /// Retourne [null] si valide, une erreur sinon.
  static ValidationError? validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.profileAddressRequired;
    }
    if (value.trim().length < 5) {
      return ValidationError.profileAddressTooShort;
    }
    if (value.trim().length > 500) {
      return ValidationError.profileAddressTooLong;
    }
    return null;
  }

  /// Valide le numéro de téléphone du bailleur.
  ///
  /// Champ facultatif. Si renseigné, regex E.164 souple :
  /// `^[+0-9 .]{6,20}$` — accepte FR (`06 12 34 56 78`) et international
  /// (`+33612345678`).
  ///
  /// Retourne [null] si valide ou vide, une erreur sinon.
  static ValidationError? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    // Regex E.164 souple — pas de validation stricte (FR ou international).
    final regex = RegExp(r'^[+0-9 .]{6,20}$');
    if (!regex.hasMatch(trimmed)) {
      return ValidationError.phoneInvalid;
    }
    return null;
  }
}
