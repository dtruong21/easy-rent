// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'investment_scenario.freezed.dart';
part 'investment_scenario.g.dart';

/// Modèle immutable d'un scénario d'investissement (FEAT-018).
///
/// Reflète la table `investment_scenarios` (16 colonnes).
/// Toutes les valeurs monétaires sont en centimes. Les taux sont en basis
/// points (bps) : 100 bps = 1 %.
@freezed
class InvestmentScenario with _$InvestmentScenario {
  const factory InvestmentScenario({
    required String id,
    @JsonKey(name: 'landlord_id') required String landlordId,
    required String name,

    /// Prix d'achat du bien (centimes, > 0).
    @JsonKey(name: 'purchase_price_cents') required int purchasePriceCents,

    /// Frais de notaire (centimes, >= 0). Standard : 8 % ancien / 2 % neuf.
    @JsonKey(name: 'notary_fees_cents') @Default(0) int notaryFeesCents,

    /// Travaux initiaux (centimes, >= 0).
    @JsonKey(name: 'works_initial_cents') @Default(0) int worksInitialCents,

    /// true = bien neuf (frais notaire réduits ~2 %).
    @JsonKey(name: 'is_new_property') @Default(false) bool isNewProperty,

    /// Apport personnel (centimes, >= 0).
    @JsonKey(name: 'down_payment_cents') @Default(0) int downPaymentCents,

    /// Capital emprunté (centimes, >= 0).
    @JsonKey(name: 'loan_principal_cents') @Default(0) int loanPrincipalCents,

    /// Taux nominal annuel du prêt (basis points, 0-3000). 350 bps = 3,5 %.
    @JsonKey(name: 'loan_rate_bps') @Default(0) int loanRateBps,

    /// Durée du prêt (mois, 12-360). Défaut 240 mois = 20 ans.
    @JsonKey(name: 'loan_duration_months') @Default(240) int loanDurationMonths,

    /// Loyer mensuel HC cible (centimes, > 0).
    @JsonKey(name: 'monthly_rent_hc_cents') required int monthlyRentHcCents,

    /// Taxe foncière annuelle (centimes, >= 0).
    @JsonKey(name: 'property_tax_annual_cents')
    @Default(0)
    int propertyTaxAnnualCents,

    /// Assurance PNO annuelle (centimes, >= 0).
    @JsonKey(name: 'insurance_pno_annual_cents')
    @Default(0)
    int insurancePnoAnnualCents,

    /// Charges copropriété non récupérables annuelles (centimes, >= 0).
    /// Gros travaux, syndic, ALUR — exclut la part récupérable sur le locataire.
    @JsonKey(name: 'condo_fees_non_recoverable_cents')
    @Default(0)
    int condoFeesNonRecoverableCents,

    /// Notes libres (max 2000 caractères, optionnel).
    String? notes,

    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _InvestmentScenario;

  factory InvestmentScenario.fromJson(Map<String, dynamic> json) =>
      _$InvestmentScenarioFromJson(json);
}
