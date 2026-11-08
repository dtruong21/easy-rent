import '../../../core/finance/profitability.dart';
import '../../properties/domain/property.dart';

/// Mensualité de prêt imputable à UN mois, pour UN bien.
///
/// Réutilise [computeLoanMonthlyPaymentCents] (`core/finance/profitability.dart`)
/// — le même moteur que le KPI « Rentabilité portfolio »
/// (`computeSnapshotForProperty`) — pour ne jamais faire diverger LE MONTANT
/// de la mensualité entre les deux écrans. [loanMonthlyPaymentOverrideCents]
/// reste prioritaire sur tout calcul, exactement comme dans
/// `computeSnapshotForProperty`.
///
/// Ce que ce module ajoute, en revanche, par rapport à `profitability.dart` :
/// la **fenêtre** du prêt. `computeSnapshotForProperty` produit un snapshot
/// au présent (une mensualité « oui/non », jamais un historique mois par
/// mois) — il n'a donc pas besoin de savoir SI un mois donné tombe avant le
/// départ du prêt ou après sa dernière échéance. Ce graphique, lui, affiche
/// plusieurs mois : appliquer la mensualité à un mois où le prêt n'existait
/// pas encore (ou n'existe plus) inventerait une charge.
///
/// Règle de fenêtre :
/// - [Property.loanStartDate] `null` → fenêtre indéterminée, **aucune
///   mensualité imputée** (on ne devine pas quand le prêt a commencé — c'est
///   la seule divergence assumée avec le KPI, qui lui ignore `loanStartDate`
///   et déduit la mensualité dès que le montant est calculable, cf. doc de
///   `computeSnapshotForProperty`).
/// - Mois strictement antérieur au mois de [Property.loanStartDate] →
///   aucune mensualité.
/// - [Property.loanDurationMonths] renseigné → dernière échéance au mois
///   `loanStartDate + (loanDurationMonths - 1)` ; tout mois postérieur
///   n'en porte aucune. Si la durée est inconnue (mais qu'un montant reste
///   calculable, ex. override seul), la fenêtre est réputée ouverte
///   indéfiniment à partir du départ — même logique que le KPI, qui ne
///   borne jamais dans le temps.
int loanMonthlyPaymentForMonthCents({
  required Property property,
  required int year,
  required int month,
}) {
  final start = property.loanStartDate;
  if (start == null) return 0;

  final target = DateTime(year, month);
  final startMonth = DateTime(start.year, start.month);
  if (target.isBefore(startMonth)) return 0;

  final durationMonths = property.loanDurationMonths;
  if (durationMonths != null && durationMonths > 0) {
    final lastMonth = DateTime(start.year, start.month + durationMonths - 1);
    if (target.isAfter(lastMonth)) return 0;
  }

  final override = property.loanMonthlyPaymentOverrideCents;
  if (override != null) return override;

  final principal = property.loanPrincipalCents;
  final rate = property.loanRateBps;
  if (principal == null || rate == null || durationMonths == null) return 0;

  return computeLoanMonthlyPaymentCents(
    principalCents: principal,
    rateBps: rate,
    durationMonths: durationMonths,
    insuranceBps: property.loanInsuranceBps ?? 0,
  );
}

/// Somme, tous biens confondus, des mensualités de prêt imputables à un
/// mois — alimente `MonthlyCashflow.loanPaymentCents`.
int sumLoanMonthlyPaymentCentsForMonth({
  required List<Property> properties,
  required int year,
  required int month,
}) => properties.fold<int>(
  0,
  (sum, property) =>
      sum +
      loanMonthlyPaymentForMonthCents(
        property: property,
        year: year,
        month: month,
      ),
);
