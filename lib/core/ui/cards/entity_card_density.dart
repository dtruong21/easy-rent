/// Densité d'affichage d'un [EntityCard].
enum EntityCardDensity {
  /// Compact : padding 12px, gap 4px.
  compact,

  /// Standard : padding 16px, gap 8px (par défaut).
  standard,
}

/// Extensions utilitaires sur [EntityCardDensity].
extension EntityCardDensityX on EntityCardDensity {
  /// Padding interne de la carte.
  double get padding => switch (this) {
    EntityCardDensity.compact => 12,
    EntityCardDensity.standard => 16,
  };

  /// Espacement vertical entre les sections (header/body/footer).
  double get gap => switch (this) {
    EntityCardDensity.compact => 4,
    EntityCardDensity.standard => 8,
  };
}
