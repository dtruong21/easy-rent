/// Enum fermé des types de documents — miroir du CHECK SQL sur `document_type`.
///
/// Valeurs SQL : `'quittance'`, `'recu'`.
enum DocumentType {
  quittance,
  recu;

  /// Valeur SQL correspondante (stockée dans Postgres).
  String get sqlValue => name;

  /// Libellé français affiché dans l'UI.
  String get label => switch (this) {
    DocumentType.quittance => 'Quittance',
    DocumentType.recu => 'Reçu',
  };

  /// Construit un [DocumentType] depuis sa valeur SQL.
  ///
  /// Retourne [quittance] par défaut si la valeur est inconnue —
  /// tolérance défensive pour données futures.
  static DocumentType fromSql(String value) => DocumentType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => DocumentType.quittance,
  );
}
