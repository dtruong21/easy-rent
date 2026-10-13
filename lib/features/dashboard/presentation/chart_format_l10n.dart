import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/chart_format.dart';

/// Mappe [ChartFormat] vers son libellé localisé (FEAT-043).
///
/// Le domaine ne porte plus de libellé FR en dur — voir la note sur
/// [ChartFormat]. Utilisé par le toggle de format de `MonthlyCashflowChart`
/// (libellé affiché en tooltip du bouton segmenté).
extension ChartFormatL10n on ChartFormat {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ChartFormat.bars => l10n.dashboardChartFormatBars,
      ChartFormat.line => l10n.dashboardChartFormatLine,
      ChartFormat.area => l10n.dashboardChartFormatArea,
    };
  }
}
