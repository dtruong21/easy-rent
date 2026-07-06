/// Mode de charges d'un bail — critère juridique réel de l'éligibilité à la
/// régularisation annuelle des charges (art. 23 loi du 6 juillet 1989), à ne
/// PAS confondre avec [LeaseType] (type de bail).
///
/// - [provisions] : provisions mensuelles refacturées au locataire, avec
///   régularisation annuelle obligatoire au réel (charges récupérables).
/// - [forfait] : montant forfaitaire mensuel libératoire — pas de
///   régularisation (le forfait "solde" définitivement les charges).
enum ChargeMode {
  provisions,
  forfait;

  /// Valeur stockée (Firestore camelCase natif = name de l'enum Dart).
  String get sqlValue => name;

  /// Libellé français affiché dans l'UI.
  String get labelFr => switch (this) {
    ChargeMode.provisions => 'Provisions + régularisation',
    ChargeMode.forfait => 'Forfait',
  };

  /// Convertit une valeur stockée vers l'enum Dart.
  ///
  /// Tolérance défensive : `null` ou valeur inconnue → `null` (le getter
  /// `LeaseExtension.effectiveChargeMode` dérive alors un mode à partir du
  /// type de bail — c'est la migration lazy sans backfill des baux pré-042).
  static ChargeMode? fromSqlOrNull(String? value) {
    if (value == null) return null;
    for (final mode in ChargeMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}
