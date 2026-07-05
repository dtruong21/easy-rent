/// Enum fermé des statuts d'un bail — miroir du CHECK SQL `('active','terminated','archived')`.
///
/// En FEAT-005, seuls `active` et `terminated` sont exposés à l'utilisateur.
/// `archived` est réservé au soft-delete futur et sert de valeur défensive
/// pour les données existantes.
enum LeaseStatus {
  active,
  terminated,
  archived;

  /// Libellé français affiché dans l'UI.
  String get labelFr => switch (this) {
    LeaseStatus.active => 'Actif',
    LeaseStatus.terminated => 'Terminé',
    LeaseStatus.archived => 'Archivé',
  };

  /// Valeur SQL correspondante (= name de l'enum Dart).
  String get sqlValue => name;

  /// Construit un [LeaseStatus] depuis sa valeur SQL.
  ///
  /// Retourne [archived] par défaut si la valeur est inconnue —
  /// tolérance défensive pour données futures.
  static LeaseStatus fromSql(String value) => LeaseStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => LeaseStatus.archived,
  );
}
