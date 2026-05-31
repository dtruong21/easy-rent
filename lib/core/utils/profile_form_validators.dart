/// Validateurs du formulaire profil bailleur — logique pure, sans dépendance
/// Flutter.
///
/// Testables unitairement sans mock. Pattern strictement aligné sur
/// [TenantFormValidators] et [PaymentFormValidators].
///
/// Conformité légale :
/// - [fullName] et [address] sont obligatoires pour générer des quittances
///   conformes à la loi 1989 art. 21.
/// - [phone] est facultatif — format libre (FR ou international acceptés).
class ProfileFormValidators {
  const ProfileFormValidators._();

  /// Valide le nom complet du bailleur.
  ///
  /// Obligatoire, longueur 2..200.
  /// Retourne [null] si valide, un message d'erreur FR sinon.
  static String? validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le nom complet est obligatoire (requis pour les quittances)';
    }
    if (value.trim().length < 2) {
      return 'Le nom complet doit contenir au moins 2 caractères';
    }
    if (value.trim().length > 200) {
      return 'Le nom complet ne peut pas dépasser 200 caractères';
    }
    return null;
  }

  /// Valide l'adresse postale du bailleur.
  ///
  /// Obligatoire, longueur 5..500. Format libre (multi-ligne accepté).
  /// Retourne [null] si valide, un message d'erreur FR sinon.
  static String? validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "L'adresse est obligatoire (requise pour les quittances)";
    }
    if (value.trim().length < 5) {
      return "L'adresse doit contenir au moins 5 caractères";
    }
    if (value.trim().length > 500) {
      return "L'adresse ne peut pas dépasser 500 caractères";
    }
    return null;
  }

  /// Valide le numéro de téléphone du bailleur.
  ///
  /// Champ facultatif. Si renseigné, regex E.164 souple :
  /// `^[+0-9 .]{6,20}$` — accepte FR (`06 12 34 56 78`) et international
  /// (`+33612345678`).
  ///
  /// Retourne [null] si valide ou vide, un message d'erreur FR sinon.
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    // Regex E.164 souple — pas de validation stricte (FR ou international).
    final regex = RegExp(r'^[+0-9 .]{6,20}$');
    if (!regex.hasMatch(trimmed)) {
      return 'Numéro de téléphone invalide (ex. : 06 12 34 56 78 ou +33612345678)';
    }
    return null;
  }
}
