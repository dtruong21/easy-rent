/// Règles fiscales LMNP (location meublée longue durée) utilisées par le
/// simulateur d'achat (FEAT-061). UNE table par loi de finances : changer de
/// loi = ajouter une table et basculer [lmnpRules2026] là où elle est lue ;
/// le calcul (`lmnp_tax_simulation.dart`) ne change pas.
///
/// Toute mise à jour se vérifie sur les sites officiels (impots.gouv.fr,
/// economie.gouv.fr, BOFiP, Légifrance), pas sur des blogs.
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

/// Règles applicables aux revenus 2026. Prélèvements sociaux 18,6 % : LFSS 2026
/// (loi n° 2025-1403 du 30 décembre 2025, art. 12 — hausse de la CSG sur les
/// revenus du patrimoine, dont les BIC de location meublée non professionnelle ;
/// les revenus fonciers restent à 17,2 %). Plafond micro-BIC 83 600 € :
/// revalorisation triennale applicable aux recettes 2026 à 2028 (art. 50-0
/// CGI).
///
/// Vérifié le 2026-11-08 sur les sites officiels :
/// - 18,6 % en location meublée (17,2 % en location nue) : impots.gouv.fr,
///   « Je donne un bien en location. Dois-je payer des prélèvements
///   sociaux ? » (modifié le 17/07/2026) ;
/// - 83 600 € pour les recettes 2026, abattement 50 % minimum 305 €, seuil
///   LMP 23 000 € : economie.gouv.fr, « Location meublée longue durée : quels
///   revenus déclarer ? ».
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
