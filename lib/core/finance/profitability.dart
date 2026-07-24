import 'dart:math' as math;

/// Compute engine de rentabilité immobilière — module pur Dart.
///
/// Aucune dépendance Flutter ou Firebase.
/// Toutes les valeurs monétaires sont en centimes (int).
/// Les taux sont exprimés en basis points (bps) : 100 bps = 1 %.

/// Mensualité d'un prêt à annuité fixe (capital + intérêts + assurance).
///
/// Formule : P × t / (1 - (1+t)^-n)
/// où t = taux mensuel, n = durée en mois.
/// Cas particulier : taux = 0 → P / n.
/// Assurance calculée sur le capital initial : P × (insuranceBps / 10000 / 12).
int computeLoanMonthlyPaymentCents({
  required int principalCents,
  required int rateBps,
  required int durationMonths,
  required int insuranceBps,
}) {
  if (principalCents <= 0 || durationMonths <= 0) return 0;
  final monthlyInsurance = (principalCents * insuranceBps / 10000 / 12).round();
  final monthlyRate = rateBps / 10000 / 12;
  final int principalPayment;
  if (monthlyRate == 0) {
    principalPayment = (principalCents / durationMonths).round();
  } else {
    final factor = math.pow(1 + monthlyRate, -durationMonths).toDouble();
    principalPayment = ((principalCents * monthlyRate) / (1 - factor)).round();
  }
  return principalPayment + monthlyInsurance;
}

/// Rendement brut = (loyer HC annuel) / (prix achat + frais notaire) × 100
///
/// Retourne [null] si le prix d'achat est manquant ou nul.
double? computeYieldGrossPercent({
  required int annualRentHcCents,
  required int? purchasePriceCents,
  required int? notaryFeesCents,
}) {
  if (purchasePriceCents == null || purchasePriceCents <= 0) return null;
  final total = purchasePriceCents + (notaryFeesCents ?? 0);
  if (total <= 0) return null;
  return (annualRentHcCents / total) * 100.0;
}

/// Rendement net = (loyer HC annuel - charges annuelles non récupérables)
///                 / coût total acquisition × 100.
///
/// Charges = taxe foncière + assurance PNO + charges copro non récupérables.
/// Retourne [null] si le prix d'achat est manquant, ou si aucune charge
/// n'est renseignée (évite un rendement net ambigu).
double? computeYieldNetPercent({
  required int annualRentHcCents,
  required int? purchasePriceCents,
  required int? notaryFeesCents,
  required int? propertyTaxAnnualCents,
  required int? insurancePnoAnnualCents,
  required int? condoFeesNonRecoverableCents,
}) {
  if (purchasePriceCents == null || purchasePriceCents <= 0) return null;
  if (propertyTaxAnnualCents == null &&
      insurancePnoAnnualCents == null &&
      condoFeesNonRecoverableCents == null) {
    return null;
  }
  final total = purchasePriceCents + (notaryFeesCents ?? 0);
  if (total <= 0) return null;
  final charges =
      (propertyTaxAnnualCents ?? 0) +
      (insurancePnoAnnualCents ?? 0) +
      (condoFeesNonRecoverableCents ?? 0);
  return ((annualRentHcCents - charges) / total) * 100.0;
}

/// Cash flow mensuel AVANT IMPÔT
/// = loyer HC mensuel - mensualité prêt - charges mensualisées.
///
/// Retourne [null] si aucune donnée de charges ou prêt n'est renseignée
/// (évite un cash flow trivial = loyer brut sans déductions).
int? computeMonthlyCashflowBeforeTaxCents({
  required int monthlyRentHcCents,
  required int? loanMonthlyPaymentCents,
  required int? propertyTaxAnnualCents,
  required int? insurancePnoAnnualCents,
  required int? condoFeesNonRecoverableCents,
}) {
  if (loanMonthlyPaymentCents == null &&
      propertyTaxAnnualCents == null &&
      insurancePnoAnnualCents == null &&
      condoFeesNonRecoverableCents == null) {
    return null;
  }
  final monthlyCharges =
      ((propertyTaxAnnualCents ?? 0) +
          (insurancePnoAnnualCents ?? 0) +
          (condoFeesNonRecoverableCents ?? 0)) ~/
      12;
  return monthlyRentHcCents - (loanMonthlyPaymentCents ?? 0) - monthlyCharges;
}
