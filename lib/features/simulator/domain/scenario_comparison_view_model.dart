import '../../../core/utils/money_format.dart';
import '../../../l10n/app_localizations.dart';
import 'investment_scenario.dart';
import 'scenario_results.dart';

/// Les 6 KPI comparés en V1 (FEAT-055).
///
/// Chaque valeur porte sa propre notion de « direction favorable » : un
/// rendement plus élevé est meilleur, un coût de crédit plus bas est meilleur.
/// Le mapping vit ici (domaine), le rendu couleur vit dans le widget cellule.
enum ComparisonKpi {
  grossYield,
  netYield,
  monthlyCashflow,
  totalLoanCost,
  downPaymentRequired,
  savingsEffort;

  bool get higherIsBetter => switch (this) {
    ComparisonKpi.grossYield => true,
    ComparisonKpi.netYield => true,
    ComparisonKpi.monthlyCashflow => true,
    ComparisonKpi.totalLoanCost => false,
    ComparisonKpi.downPaymentRequired => false,
    ComparisonKpi.savingsEffort => false,
  };
}

/// Valeur atomique d'un KPI pour un scénario donné.
///
/// [rawNumber] est la grandeur brute utilisée pour calculer le delta %.
/// [display] est le libellé formaté prêt à peindre.
class ComparisonValue {
  const ComparisonValue({required this.rawNumber, required this.display});
  final double rawNumber;
  final String display;
}

/// Une ligne de la table de comparaison = un KPI + N valeurs (une par scénario).
class ComparisonRow {
  const ComparisonRow({
    required this.kpi,
    required this.label,
    required this.values,
  });
  final ComparisonKpi kpi;
  final String label;
  final List<ComparisonValue> values;
}

/// Construit les 6 lignes de comparaison pour N scénarios (2 ou 3, ordre
/// préservé). Fonction pure, appelable depuis un test unitaire sans widget.
List<ComparisonRow> buildComparisonRows(
  List<InvestmentScenario> ordered,
  AppLocalizations l10n,
) {
  final results = ordered.map(computeScenarioResults).toList();
  final effortSuffix = l10n.simulatorCompareEffortPerYearSuffix;

  ComparisonValue percentValue(double v) => ComparisonValue(
    rawNumber: v,
    display: '${v.toStringAsFixed(2).replaceAll('.', ',')} %',
  );
  ComparisonValue centsValue(int c) => ComparisonValue(
    rawNumber: c.toDouble(),
    display: MoneyFormat.formatEurosFromCents(c),
  );
  ComparisonValue effortValue(int c) => ComparisonValue(
    rawNumber: c.toDouble(),
    display: '${MoneyFormat.formatEurosFromCents(c)} $effortSuffix',
  );

  return [
    ComparisonRow(
      kpi: ComparisonKpi.grossYield,
      label: l10n.simulatorKpiGrossYieldLabel,
      values: [for (final r in results) percentValue(r.yieldGrossPercent)],
    ),
    ComparisonRow(
      kpi: ComparisonKpi.netYield,
      label: l10n.simulatorKpiNetYieldLabel,
      values: [for (final r in results) percentValue(r.yieldNetPercent)],
    ),
    ComparisonRow(
      kpi: ComparisonKpi.monthlyCashflow,
      label: l10n.simulatorKpiMonthlyCashflowLabel,
      values: [
        for (final r in results) centsValue(r.monthlyCashflowBeforeTaxCents),
      ],
    ),
    ComparisonRow(
      kpi: ComparisonKpi.totalLoanCost,
      label: l10n.simulatorKpiTotalLoanCostLabel,
      values: [for (final r in results) centsValue(r.totalLoanCostCents)],
    ),
    ComparisonRow(
      kpi: ComparisonKpi.downPaymentRequired,
      label: l10n.simulatorCompareKpiDownPaymentLabel,
      values: [for (final s in ordered) centsValue(s.downPaymentCents)],
    ),
    ComparisonRow(
      kpi: ComparisonKpi.savingsEffort,
      label: l10n.simulatorCompareKpiSavingsEffortLabel,
      values: [
        for (final r in results)
          effortValue(
            computeAnnualSavingsEffortCents(r.monthlyCashflowBeforeTaxCents),
          ),
      ],
    ),
  ];
}

/// Effort d'épargne annualisé en centimes.
///
/// = `max(0, -cashflowMensuel) × 12`. Un scénario auto-financé (cash-flow ≥ 0)
/// donne 0 €/an. Décision P3 validée par le PO le 2026-07-23.
int computeAnnualSavingsEffortCents(int monthlyCashflowCents) {
  if (monthlyCashflowCents >= 0) return 0;
  return -monthlyCashflowCents * 12;
}

/// Delta signé de [other] vs. [reference] en pourcentage.
///
/// Divise par `reference.abs()` pour préserver la sémantique « + = higher que
/// la référence » même quand la référence est négative (utile pour le
/// cash-flow, qui peut être signé). Retourne `null` si [reference] == 0.
double? computeSignedDeltaPercent(double reference, double other) {
  if (reference == 0) return null;
  return ((other - reference) / reference.abs()) * 100.0;
}
