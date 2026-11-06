import 'dart:math' as math;

import '../../../core/finance/profitability.dart';
import 'investment_scenario.dart';
import 'lmnp_tax_rules.dart';
import 'scenario_results.dart';

enum LmnpRegime { micro, reel }

class LmnpYear {
  const LmnpYear({
    required this.year,
    required this.taxableCents,
    required this.incomeTaxCents,
    required this.socialCents,
    required this.cashflowAfterTaxCents,
  });
  final int year;
  final int taxableCents;
  final int incomeTaxCents;
  final int socialCents;
  final int cashflowAfterTaxCents;
  int get totalTaxCents => incomeTaxCents + socialCents;
}

class LmnpRegimeResult {
  const LmnpRegimeResult({required this.available, required this.years});
  final bool available;
  final List<LmnpYear> years;
  int get totalTaxCents => years.fold(0, (s, y) => s + y.totalTaxCents);
  int get totalCashflowAfterTaxCents =>
      years.fold(0, (s, y) => s + y.cashflowAfterTaxCents);
}

class LmnpTaxSimulation {
  const LmnpTaxSimulation({
    required this.micro,
    required this.reel,
    required this.annualRentCents,
    required this.rules,
  });
  final LmnpRegimeResult micro;
  final LmnpRegimeResult reel;
  final int annualRentCents;
  final LmnpTaxRules rules;
  bool get lmpAlert => annualRentCents > rules.lmpAlertCents;
  LmnpRegime get best =>
      !micro.available || reel.totalTaxCents < micro.totalTaxCents
      ? LmnpRegime.reel
      : LmnpRegime.micro;
}

LmnpTaxSimulation simulateLmnpTax(
  InvestmentScenario s, {
  LmnpTaxRules rules = lmnpRules2026,
  int years = 10,
}) {
  final rent = s.monthlyRentHcCents * 12;
  final fixedCharges =
      s.propertyTaxAnnualCents +
      s.insurancePnoAnnualCents +
      s.condoFeesNonRecoverableCents;
  final loan = _loanYears(s, years);

  int incomeTax(int taxable) => (taxable * s.tmiPercent / 100).round();
  int social(int taxable) =>
      (taxable * rules.socialRatePermille / 1000).round();
  LmnpYear row(int y, int taxable, int cashflowBefore) {
    final it = incomeTax(taxable), ps = social(taxable);
    return LmnpYear(
      year: y,
      taxableCents: taxable,
      incomeTaxCents: it,
      socialCents: ps,
      cashflowAfterTaxCents: cashflowBefore - it - ps,
    );
  }

  // Micro-BIC.
  final abatement = math.max(
    (rent * rules.microAbatementPercent / 100).round(),
    rules.microMinAbatementCents,
  );
  final microTaxable = math.max(rent - abatement, 0);

  // Réel : dotations annuelles par composant.
  final building =
      (s.purchasePriceCents *
              (100 - s.landSharePercent) /
              100 /
              rules.buildingYears)
          .round();
  final works = (s.worksInitialCents / rules.worksYears).round();
  final furniture = (s.furnitureCents / rules.furnitureYears).round();

  final micro = <LmnpYear>[], reel = <LmnpYear>[];
  final deficits = <({int year, int amount})>[];
  var amortCarry = 0;
  for (var y = 1; y <= years; y++) {
    final l = loan[y - 1];
    final cashflowBefore = rent - fixedCharges - l.paymentsCents;
    micro.add(row(y, microTaxable, cashflowBefore));

    final dotation =
        (y <= rules.buildingYears ? building : 0) +
        (y <= rules.worksYears ? works : 0) +
        (y <= rules.furnitureYears ? furniture : 0);
    final charges =
        fixedCharges +
        l.interestCents +
        l.insuranceCents +
        (y == 1 ? s.notaryFeesCents : 0);
    var result = rent - charges;
    deficits.removeWhere((d) => y - d.year > rules.deficitCarryYears);
    var taxable = 0;
    if (result < 0) {
      deficits.add((year: y, amount: -result));
      amortCarry += dotation;
    } else {
      for (var i = 0; i < deficits.length && result > 0; i++) {
        final used = math.min(deficits[i].amount, result);
        deficits[i] = (
          year: deficits[i].year,
          amount: deficits[i].amount - used,
        );
        result -= used;
      }
      deficits.removeWhere((d) => d.amount == 0);
      final available = amortCarry + dotation;
      final deducted = math.min(available, result);
      amortCarry = available - deducted;
      taxable = result - deducted;
    }
    reel.add(row(y, taxable, cashflowBefore));
  }
  return LmnpTaxSimulation(
    micro: LmnpRegimeResult(
      available: rent <= rules.microCeilingCents,
      years: micro,
    ),
    reel: LmnpRegimeResult(available: true, years: reel),
    annualRentCents: rent,
    rules: rules,
  );
}

/// Intérêts, assurance et mensualités payés chaque année (échéancier à
/// mensualité constante, même mensualité que `computeScenarioResults`).
List<({int interestCents, int insuranceCents, int paymentsCents})> _loanYears(
  InvestmentScenario s,
  int years,
) {
  final p = s.loanPrincipalCents;
  final payment = computeLoanMonthlyPaymentCents(
    principalCents: p,
    rateBps: s.loanRateBps,
    durationMonths: s.loanDurationMonths,
    insuranceBps: kScenarioLoanInsuranceBps,
  );
  final monthlyInsurance = p > 0
      ? (p * kScenarioLoanInsuranceBps / 10000 / 12).round()
      : 0;
  final rate = s.loanRateBps / 10000 / 12;
  var balance = p.toDouble();
  return [
    for (var y = 0; y < years; y++)
      () {
        var interest = 0.0, months = 0;
        for (var m = 0; m < 12; m++) {
          if (p <= 0 || y * 12 + m >= s.loanDurationMonths) continue;
          final i = balance * rate;
          interest += i;
          balance -= (payment - monthlyInsurance) - i;
          months++;
        }
        return (
          interestCents: interest.round(),
          insuranceCents: monthlyInsurance * months,
          paymentsCents: payment * months,
        );
      }(),
  ];
}
