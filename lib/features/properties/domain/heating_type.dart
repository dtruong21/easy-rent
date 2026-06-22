/// Types de chauffage — enum Dart fermé aligné sur le CHECK SQL.
///
/// IMPORTANT : si une nouvelle valeur est ajoutée côté SQL (CHECK constraint
/// sur `properties.heating_type`), elle DOIT être ajoutée ici aussi.
/// Le fallback [other] tolère gracieusement une valeur SQL inconnue.
enum HeatingType {
  electric,
  gas,
  collective,
  fuel,
  wood,
  heatPump,
  other;

  /// Valeur stockée en base (correspond exactement au CHECK SQL).
  String get sqlValue => switch (this) {
    HeatingType.heatPump => 'heat_pump',
    _ => name,
  };

  /// Libellé français affiché dans l'UI.
  String get labelFr => switch (this) {
    HeatingType.electric => 'Électrique',
    HeatingType.gas => 'Gaz',
    HeatingType.collective => 'Collectif',
    HeatingType.fuel => 'Fioul',
    HeatingType.wood => 'Bois',
    HeatingType.heatPump => 'Pompe à chaleur',
    HeatingType.other => 'Autre',
  };

  /// Convertit une valeur SQL vers l'enum Dart.
  ///
  /// Retourne [null] si [value] est null.
  /// Fallback sur [other] si la valeur est inconnue (tolérance au drift SQL).
  static HeatingType? fromSql(String? value) {
    if (value == null) return null;
    if (value == 'heat_pump') return HeatingType.heatPump;
    return HeatingType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => HeatingType.other,
    );
  }
}
