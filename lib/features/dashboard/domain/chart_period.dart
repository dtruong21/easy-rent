/// Période affichée par le graphique « Loyers ».
///
/// Choisie via le toggle de `MonthlyBarchart`, persistée par
/// `chartPeriodProvider` (localStorage sur le web).
enum ChartPeriod {
  /// 6 derniers mois (défaut historique).
  m6,

  /// 12 derniers mois.
  m12,

  /// 24 derniers mois.
  m24;

  /// Nombre de mois couverts par la période.
  int get months => switch (this) {
    ChartPeriod.m6 => 6,
    ChartPeriod.m12 => 12,
    ChartPeriod.m24 => 24,
  };

  /// Libellé affiché dans l'UI française (tooltips du toggle).
  String get labelFr => switch (this) {
    ChartPeriod.m6 => '6 mois',
    ChartPeriod.m12 => '12 mois',
    ChartPeriod.m24 => '24 mois',
  };

  /// Parse la valeur persistée. Retourne `null` si inconnue.
  static ChartPeriod? fromName(String? raw) {
    if (raw == null) return null;
    for (final p in ChartPeriod.values) {
      if (p.name == raw) return p;
    }
    return null;
  }
}
