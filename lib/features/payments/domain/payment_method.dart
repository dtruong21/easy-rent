/// Enum fermé des modes de paiement — miroir du CHECK SQL sur `payment_method`.
///
/// Valeurs SQL : `'virement'`, `'cheque'`, `'especes'`, `'prelevement'`, `'autre'`.
enum PaymentMethod {
  virement,
  cheque,
  especes,
  prelevement,
  autre;

  /// Valeur SQL correspondante (stockée dans Postgres).
  String get sqlValue => name;

  /// Libellé français affiché dans l'UI.
  String get label => switch (this) {
    PaymentMethod.virement => 'Virement',
    PaymentMethod.cheque => 'Chèque',
    PaymentMethod.especes => 'Espèces',
    PaymentMethod.prelevement => 'Prélèvement automatique',
    PaymentMethod.autre => 'Autre',
  };

  /// Construit un [PaymentMethod] depuis sa valeur SQL.
  ///
  /// Retourne [autre] par défaut si la valeur est inconnue —
  /// tolérance défensive pour données futures.
  static PaymentMethod fromSql(String value) => PaymentMethod.values.firstWhere(
    (e) => e.name == value,
    orElse: () => PaymentMethod.autre,
  );
}
