// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../features/properties/domain/property.dart';
import 'profitability.dart';

part 'profitability_snapshot.freezed.dart';
part 'profitability_snapshot.g.dart';

/// Snapshot de rentabilité calculé pour un bien immobilier.
///
/// Produit par [computeSnapshotForProperty]. Immutable (freezed).
/// [isComputable] : false si des données critiques manquent.
/// [missingFields] : liste des champs absents bloquant le calcul.
@freezed
class ProfitabilitySnapshot with _$ProfitabilitySnapshot {
  const factory ProfitabilitySnapshot({
    /// false si données manquantes critiques (pas de prix d'achat ou pas de bail).
    required bool isComputable,

    /// Champs manquants bloquant le calcul (ex. 'purchase_price', 'active_lease').
    required List<String> missingFields,

    /// Rendement brut (%) — null si prix d'achat absent.
    double? yieldGrossPercent,

    /// Rendement net avant impôt (%) — null si charges manquantes.
    double? yieldNetPercent,

    /// Cash flow mensuel avant impôt (centimes) — null si pas de données.
    int? monthlyCashflowBeforeTaxCents,

    /// Mensualité du prêt (centimes) — null si pas de prêt renseigné.
    int? loanMonthlyPaymentCents,
  }) = _ProfitabilitySnapshot;

  factory ProfitabilitySnapshot.fromJson(Map<String, dynamic> json) =>
      _$ProfitabilitySnapshotFromJson(json);
}

/// Calcule le snapshot de rentabilité pour un bien et son bail actif.
///
/// [property] : bien immobilier avec ses données financières FEAT-017.
/// [monthlyRentHcCents] : loyer hors charges du bail actif, ou null si vacant.
///
/// Retourne un snapshot avec [isComputable] = false si :
/// - pas de bail actif ([monthlyRentHcCents] == null)
/// - prix d'achat manquant
ProfitabilitySnapshot computeSnapshotForProperty({
  required Property property,
  required int? monthlyRentHcCents,
}) {
  // Cas : bien vacant (aucun bail actif).
  if (monthlyRentHcCents == null) {
    return const ProfitabilitySnapshot(
      isComputable: false,
      missingFields: ['active_lease'],
    );
  }

  final missing = <String>[];
  if (property.purchasePriceCents == null) {
    missing.add('purchase_price');
  }

  final annualRent = monthlyRentHcCents * 12;

  // Calcul mensualité prêt si données disponibles.
  final int? loanPayment;
  if (property.loanMonthlyPaymentOverrideCents != null) {
    loanPayment = property.loanMonthlyPaymentOverrideCents;
  } else if (property.loanPrincipalCents != null &&
      property.loanRateBps != null &&
      property.loanDurationMonths != null) {
    loanPayment = computeLoanMonthlyPaymentCents(
      principalCents: property.loanPrincipalCents!,
      rateBps: property.loanRateBps!,
      durationMonths: property.loanDurationMonths!,
      insuranceBps: property.loanInsuranceBps ?? 0,
    );
  } else {
    loanPayment = null;
  }

  return ProfitabilitySnapshot(
    isComputable: missing.isEmpty,
    missingFields: missing,
    yieldGrossPercent: computeYieldGrossPercent(
      annualRentHcCents: annualRent,
      purchasePriceCents: property.purchasePriceCents,
      notaryFeesCents: property.notaryFeesCents,
    ),
    yieldNetPercent: computeYieldNetPercent(
      annualRentHcCents: annualRent,
      purchasePriceCents: property.purchasePriceCents,
      notaryFeesCents: property.notaryFeesCents,
      propertyTaxAnnualCents: property.propertyTaxAnnualCents,
      insurancePnoAnnualCents: property.insurancePnoAnnualCents,
      condoFeesNonRecoverableCents: property.condoFeesNonRecoverableCents,
    ),
    monthlyCashflowBeforeTaxCents: computeMonthlyCashflowBeforeTaxCents(
      monthlyRentHcCents: monthlyRentHcCents,
      loanMonthlyPaymentCents: loanPayment,
      propertyTaxAnnualCents: property.propertyTaxAnnualCents,
      insurancePnoAnnualCents: property.insurancePnoAnnualCents,
      condoFeesNonRecoverableCents: property.condoFeesNonRecoverableCents,
    ),
    loanMonthlyPaymentCents: loanPayment,
  );
}
