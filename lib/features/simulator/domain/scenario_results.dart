import 'dart:math' as math;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/finance/profitability.dart';
import 'investment_scenario.dart';

part 'scenario_results.freezed.dart';

/// Constantes de calcul du simulateur (v1 — valeurs figées, non modifiables).
///
/// Vacancy 5 % : taux de vacance locative moyen FR (hypothèse prudente).
/// Appreciation 1,5 %/an : valorisation long terme dans villes secondaires FR.
/// Projection 240 mois = 20 ans : horizon classique d'un investissement locatif.
/// Assurance emprunteur 30 bps (0,30 %/an) : tarif moyen délégation assurance.
const double _kVacancyRatePercent = 5.0;
const double _kAnnualAppreciationPercent = 1.5;
const int _kProjectionMonths = 240;
const int _kInsuranceBps = 30;

/// 8 KPI du simulateur d'investissement (FEAT-018).
///
/// Produit par [computeScenarioResults]. Immutable (freezed).
/// Toutes les valeurs monétaires sont en centimes.
@freezed
class ScenarioResults with _$ScenarioResults {
  const factory ScenarioResults({
    /// KPI 1 — Mensualité totale prêt (capital + intérêts + assurance).
    required int loanMonthlyPaymentCents,

    /// KPI 2 — Loyer net annuel après vacance locative (5 %).
    required int annualRentNetCents,

    /// KPI 3 — Cash-flow mensuel AVANT IMPÔT.
    required int monthlyCashflowBeforeTaxCents,

    /// KPI 4 — Rendement brut (%).
    required double yieldGrossPercent,

    /// KPI 5 — Rendement net avant impôt (%).
    required double yieldNetPercent,

    /// KPI 6 — Total intérêts versés sur la durée du prêt.
    required int totalInterestPaidCents,

    /// KPI 7 — Coût total crédit (capital + intérêts + assurance × durée).
    required int totalLoanCostCents,

    /// KPI 8 — Valeur estimée du bien à terme (appreciation 1,5 %/an × 20 ans).
    required int estimatedValueAtEndCents,
  }) = _ScenarioResults;
}

/// Calcule les 8 KPI du simulateur depuis un [InvestmentScenario].
///
/// Réutilise les fonctions du module [profitability.dart] (FEAT-017).
/// Vacance fixée à 5 %, appréciation 1,5 %/an, projection 20 ans (240 mois),
/// assurance emprunteur 30 bps sur capital initial.
///
/// Edge cases :
/// - prix d'achat nul ou durée nulle → mensualité 0, rendements 0.
/// - capital emprunté nul → intérêts/coût 0.
ScenarioResults computeScenarioResults(InvestmentScenario s) {
  // ── Acquisition totale ──────────────────────────────────────────────────
  final totalAcquisition =
      s.purchasePriceCents + s.notaryFeesCents + s.worksInitialCents;

  // ── Mensualité prêt ──────────────────────────────────────────────────────
  final loanPayment = computeLoanMonthlyPaymentCents(
    principalCents: s.loanPrincipalCents,
    rateBps: s.loanRateBps,
    durationMonths: s.loanDurationMonths,
    insuranceBps: _kInsuranceBps,
  );

  // ── Revenus locatifs ─────────────────────────────────────────────────────
  // Loyer annuel brut (HC).
  final annualRentGross = s.monthlyRentHcCents * 12;
  // Loyer net vacance 5 %.
  final annualRentNet = (annualRentGross * (1.0 - _kVacancyRatePercent / 100))
      .round();

  // ── Charges annuelles ────────────────────────────────────────────────────
  final annualCharges =
      s.propertyTaxAnnualCents +
      s.insurancePnoAnnualCents +
      s.condoFeesNonRecoverableCents;

  // ── Rendements ───────────────────────────────────────────────────────────
  // Rendement brut : loyer annuel brut / coût total acquisition.
  final double yieldGross;
  if (totalAcquisition > 0) {
    yieldGross = (annualRentGross / totalAcquisition) * 100.0;
  } else {
    yieldGross = 0.0;
  }

  // Rendement net : (loyer annuel net - charges) / coût total acquisition.
  final double yieldNet;
  if (totalAcquisition > 0) {
    yieldNet = ((annualRentNet - annualCharges) / totalAcquisition) * 100.0;
  } else {
    yieldNet = 0.0;
  }

  // ── Cash-flow mensuel avant impôt ────────────────────────────────────────
  final monthlyCharges = annualCharges ~/ 12;
  final cashflow = s.monthlyRentHcCents - loanPayment - monthlyCharges;

  // ── Coût total crédit ────────────────────────────────────────────────────
  // Mensualité × durée = total remboursé (capital + intérêts + assurance).
  final totalRepaid = loanPayment * s.loanDurationMonths;
  final totalInterest = math.max(0, totalRepaid - s.loanPrincipalCents);
  // Assurance = capital × (insuranceBps / 10000) × durée en années.
  final totalInsurance =
      (s.loanPrincipalCents *
              _kInsuranceBps /
              10000 *
              (s.loanDurationMonths / 12))
          .round();
  final totalLoanCost = s.loanPrincipalCents + totalInterest + totalInsurance;

  // ── Valeur estimée à terme ───────────────────────────────────────────────
  // V_n = V_0 × (1 + r)^n  avec r = 1,5 %/an, n = 20 ans.
  final years = _kProjectionMonths / 12;
  final estimatedValue =
      (s.purchasePriceCents *
              math.pow(1 + _kAnnualAppreciationPercent / 100, years))
          .round();

  return ScenarioResults(
    loanMonthlyPaymentCents: loanPayment,
    annualRentNetCents: annualRentNet,
    monthlyCashflowBeforeTaxCents: cashflow,
    yieldGrossPercent: yieldGross,
    yieldNetPercent: yieldNet,
    totalInterestPaidCents: totalInterest,
    totalLoanCostCents: totalLoanCost,
    estimatedValueAtEndCents: estimatedValue,
  );
}
