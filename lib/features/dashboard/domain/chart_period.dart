/// Période affichée par le graphique « Loyers ».
///
/// Choisie via le toggle de `MonthlyBarchart`, persistée par
/// `chartPeriodProvider` (localStorage sur le web).
///
/// FEAT-043 : cet enum ne porte plus de libellé FR en dur — la présentation
/// mappe chaque valeur vers `context.l10n.<clé>` via l'extension
/// `ChartPeriodL10n` (`lib/features/dashboard/presentation/chart_period_l10n.dart`).
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

  /// Parse la valeur persistée. Retourne `null` si inconnue.
  static ChartPeriod? fromName(String? raw) {
    if (raw == null) return null;
    for (final p in ChartPeriod.values) {
      if (p.name == raw) return p;
    }
    return null;
  }
}
