/// Règles fiscales LMNP (location meublée longue durée) utilisées par le
/// simulateur d'achat (FEAT-061). UNE table par loi de finances : changer de
/// loi = ajouter une table et basculer [lmnpRules2026] là où elle est lue ;
/// le calcul (`lmnp_tax_simulation.dart`) ne change pas.
///
/// Sources à confirmer sur Légifrance / BOFiP avant toute mise à jour.
library;

/// Tranches marginales d'imposition proposées à la saisie.
const List<int> kTmiChoices = [0, 11, 30, 41, 45];

class LmnpTaxRules {
  const LmnpTaxRules({
    required this.label,
    required this.microAbatementPercent,
    required this.microMinAbatementCents,
    required this.microCeilingCents,
    required this.socialRatePermille,
    required this.buildingYears,
    required this.worksYears,
    required this.furnitureYears,
    required this.lmpAlertCents,
    required this.deficitCarryYears,
  });

  /// Affiché dans l'UI (« Règles 2026 »).
  final String label;
  final int microAbatementPercent;
  final int microMinAbatementCents;

  /// Au-delà de ces recettes annuelles, le micro-BIC n'est pas disponible.
  final int microCeilingCents;

  /// Prélèvements sociaux, en pour mille (186 = 18,6 %).
  final int socialRatePermille;
  final int buildingYears;
  final int worksYears;
  final int furnitureYears;

  /// Recettes annuelles au-delà desquelles le statut LMP peut s'appliquer.
  final int lmpAlertCents;

  /// Durée de report d'un déficit hors amortissement.
  final int deficitCarryYears;
}

/// Loi de finances 2026 (promulguée en février 2026) + LFSS 2026.
const LmnpTaxRules lmnpRules2026 = LmnpTaxRules(
  label: 'Règles 2026',
  microAbatementPercent: 50,
  microMinAbatementCents: 30500,
  microCeilingCents: 8360000,
  socialRatePermille: 186,
  buildingYears: 30,
  worksYears: 15,
  furnitureYears: 7,
  lmpAlertCents: 2300000,
  deficitCarryYears: 10,
);
