/// Format d'affichage du graphique « Cash-flow mensuel » (période variable,
/// cf. [ChartPeriod]).
///
/// Choisi via le toggle de [MonthlyCashflowChart], persisté par
/// `chartFormatProvider` (localStorage sur le web).
///
/// FEAT-043 : cet enum ne porte plus de libellé FR en dur — la présentation
/// mappe chaque valeur vers `context.l10n.<clé>` via l'extension
/// `ChartFormatL10n` (`lib/features/dashboard/presentation/chart_format_l10n.dart`).
enum ChartFormat {
  /// Barres groupées (défaut historique).
  bars,

  /// Courbes (tendance).
  line,

  /// Courbes avec aires remplies (volume).
  area;

  /// Parse la valeur persistée. Retourne `null` si inconnue.
  static ChartFormat? fromName(String? raw) {
    if (raw == null) return null;
    for (final f in ChartFormat.values) {
      if (f.name == raw) return f;
    }
    return null;
  }
}
