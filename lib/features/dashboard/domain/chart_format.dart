/// Format d'affichage du graphique « Loyers — 6 derniers mois ».
///
/// Choisi via le toggle de [MonthlyBarchart], persisté par
/// `chartFormatProvider` (localStorage sur le web).
enum ChartFormat {
  /// Barres groupées (défaut historique).
  bars,

  /// Courbes (tendance).
  line,

  /// Courbes avec aires remplies (volume).
  area;

  /// Libellé affiché dans l'UI française (tooltips du toggle).
  String get labelFr => switch (this) {
    ChartFormat.bars => 'Barres',
    ChartFormat.line => 'Courbes',
    ChartFormat.area => 'Aires',
  };

  /// Parse la valeur persistée. Retourne `null` si inconnue.
  static ChartFormat? fromName(String? raw) {
    if (raw == null) return null;
    for (final f in ChartFormat.values) {
      if (f.name == raw) return f;
    }
    return null;
  }
}
