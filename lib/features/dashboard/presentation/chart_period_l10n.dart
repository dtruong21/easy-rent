import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/chart_period.dart';

/// Mappe [ChartPeriod] vers son libellé localisé (FEAT-043).
///
/// Le domaine ne porte plus de libellé FR en dur — voir la note sur
/// [ChartPeriod]. Utilisé par le toggle de période de `MonthlyBarchart`.
extension ChartPeriodL10n on ChartPeriod {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ChartPeriod.m6 => l10n.dashboardChartPeriod6Months,
      ChartPeriod.m12 => l10n.dashboardChartPeriod12Months,
      ChartPeriod.m24 => l10n.dashboardChartPeriod24Months,
    };
  }
}
