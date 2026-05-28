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
}
