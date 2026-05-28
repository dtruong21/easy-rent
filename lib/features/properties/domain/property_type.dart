/// Types de biens immobiliers — enum Dart fermé aligné sur le CHECK SQL.
///
/// IMPORTANT : si une nouvelle valeur est ajoutée côté SQL (CHECK constraint
/// sur `properties.type`), elle DOIT être ajoutée ici aussi pour rester en sync.
/// Le fallback [autre] tolère gracieusement une valeur SQL inconnue.
enum PropertyType {
  appartement,
  maison,
  studio,
  autre;

  /// Libellé français affiché dans l'UI.
  String get labelFr => switch (this) {
    PropertyType.appartement => 'Appartement',
    PropertyType.maison => 'Maison',
    PropertyType.studio => 'Studio',
    PropertyType.autre => 'Autre',
  };

  /// Valeur stockée en base (correspond exactement au CHECK SQL).
  String get sqlValue => name;

  /// Convertit une valeur SQL vers l'enum Dart.
  ///
  /// Fallback sur [autre] si la valeur est inconnue (tolérance au drift SQL).
  static PropertyType fromSql(String value) => PropertyType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => PropertyType.autre,
  );
}
