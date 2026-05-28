import 'email_validator.dart';

/// Validateurs du formulaire locataire — logique pure, sans dépendance Flutter.
///
/// Testables unitairement sans mock. Même pattern que les validateurs de `properties`
/// (volontairement séparés tant qu'on n'a pas 3+ usages d'un validateur partagé).
///
/// Note : [validatePhone] retourne toujours `null` en V1 (string libre acceptée).
/// Le hook est en place pour une évolution future (regex internationale ou package
/// `phone_validator` en P1).
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
}
