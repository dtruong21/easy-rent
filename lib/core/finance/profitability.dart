import 'dart:math' as math;

import 'real_expense_charges.dart';

/// Compute engine de rentabilité immobilière — module pur Dart.
///
/// Aucune dépendance Flutter ou Firebase.
/// Toutes les valeurs monétaires sont en centimes (int).
/// Les taux sont exprimés en basis points (bps) : 100 bps = 1 %.
///
/// ## Cash flow réel vs prévisionnel (dépenses réelles)
///
/// [computeMonthlyCashflowBeforeTaxCents] peut intégrer les dépenses réelles
/// saisies (`features/expenses`, FEAT-041) au lieu des seules charges
/// annuelles déclarées sur le bien. Règle retenue, **explicable en une
/// phrase** : pour chacune des 3 charges ayant un équivalent déclaré sur le
/// bien (taxe foncière, assurance PNO, charges de copropriété non
/// récupérables), le cash flow utilise la somme de vos dépenses réelles des
/// 12 derniers mois glissants dès que vous suivez cette charge depuis au
/// moins un an ; sinon il repose sur le montant annuel déclaré sur la fiche
/// du bien.
///
/// Pourquoi une bascule **par catégorie de charge** et non globale : une
/// dépense isolée de faible montant (ex. 50 €) ne doit pas remplacer une
/// charge annuelle bien plus élevée (ex. 1200 € de taxe foncière) sur un
/// autre poste — un remplacement agrégé ferait passer un cash flow correct
/// pour faussement excellent dès la première saisie. En traitant chaque
/// charge indépendamment, une dépense isolée ne peut déplacer que SON
/// propre poste, jamais les deux autres.
///
/// Pourquoi un **seuil de couverture temporelle** (12 mois d'historique,
/// pas juste « au moins une dépense ») plutôt qu'un seuil sur le nombre de
/// dépenses : la taxe foncière ou l'assurance PNO sont légitimement payées
/// en une seule fois par an — exiger plusieurs saisies bloquerait
/// indéfiniment la bascule pour ces charges. Exiger à la place qu'on
/// dispose d'un an de recul (la dépense la plus ancienne de cette nature
/// remonte à 12 mois ou plus) garantit que la fenêtre glissante n'est pas
/// un instantané tronqué : soit on a du recul et on fait confiance au réel,
/// soit on n'en a pas encore et on garde le prévisionnel déclaré.
///
/// ## Dépenses récurrentes : bascule immédiate (FEAT-041d)
///
/// Une charge **récurrente en cours** (`ExpenseRecurrence` ≠ `none`, cf.
/// `expense_recurrence.dart`) fait basculer sa catégorie sur le réel
/// **immédiatement**, sans attendre les 12 mois de recul exigés des
/// dépenses ponctuelles.
///
/// Le seuil de recul existe parce qu'une dépense ponctuelle est un
/// **échantillon** : une facture de 50 € ne dit rien du total annuel de ce
/// poste, et la laisser écraser une taxe foncière de 1200 € déclarée sur le
/// bien transformerait un cash flow correct en cash flow faussement
/// excellent. Une récurrence n'est pas un échantillon, c'est une
/// **déclaration** : « charges de copropriété, 150 € par trimestre » est du
/// même ordre de fiabilité que le montant annuel saisi sur la fiche du bien,
/// et il est plus frais. Attendre un an pour l'utiliser reviendrait à
/// préférer sciemment l'estimation la plus ancienne des deux.
///
/// Le montant retenu suit la même logique. Tant que la récurrence est en
/// cours, la charge annuelle vaut `montant × échéances par an` (600 € pour
/// 150 €/trimestre) — pas la somme de ses échéances déjà tombées dans la
/// fenêtre glissante, qui vaudrait 150 € le jour de la saisie et
/// sous-estimerait la charge de 75 % pendant neuf mois. Une fois la
/// récurrence **terminée** (date de fin dépassée), elle redevient de
/// l'histoire : seules comptent ses échéances réellement tombées dans les
/// 12 derniers mois, exactement comme des dépenses ponctuelles.
///
/// Seules les dépenses **non récupérables** comptent : les charges
/// récupérables sont refacturées au locataire via la régularisation
/// annuelle, elles ne représentent pas une sortie de cash flow nette pour
/// le bailleur (cohérent avec `condoFeesNonRecoverableCents`, déjà nommé
/// ainsi côté prévisionnel).
///
/// Les rendements brut et net ne changent pas de définition : seul le cash
/// flow intègre les dépenses réelles (cf. [ProfitabilitySnapshot]).
const Duration kRealExpensesRollingWindow = Duration(days: 365);

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
/// Les charges mensualisées viennent, poste par poste (taxe foncière,
/// assurance PNO, charges copro non récupérables), soit de [realCharges]
/// (dépenses réelles lissées sur 12 mois glissants) soit du montant annuel
/// déclaré sur le bien — voir la doc de tête de fichier pour la règle de
/// bascule complète.
///
/// Retourne [null] si aucune donnée de charges ou prêt n'est renseignée, ni
/// réelle ni déclarée (évite un cash flow trivial = loyer brut sans
/// déductions).
///
/// [now] est injectable pour les tests (évite la dépendance à
/// `DateTime.now()`).
int? computeMonthlyCashflowBeforeTaxCents({
  required int monthlyRentHcCents,
  required int? loanMonthlyPaymentCents,
  required int? propertyTaxAnnualCents,
  required int? insurancePnoAnnualCents,
  required int? condoFeesNonRecoverableCents,
  PropertyRealCharges realCharges = PropertyRealCharges.empty,
  DateTime? now,
}) {
  final buckets = _resolveCharges(
    propertyTaxAnnualCents: propertyTaxAnnualCents,
    insurancePnoAnnualCents: insurancePnoAnnualCents,
    condoFeesNonRecoverableCents: condoFeesNonRecoverableCents,
    realCharges: realCharges,
    now: now ?? DateTime.now(),
  );

  if (loanMonthlyPaymentCents == null && buckets.every((b) => !b.usable)) {
    return null;
  }

  final annualChargesCents = buckets.fold<int>(
    0,
    (sum, b) => sum + b.annualCents,
  );
  final monthlyCharges = annualChargesCents ~/ 12;
  return monthlyRentHcCents - (loanMonthlyPaymentCents ?? 0) - monthlyCharges;
}

/// Nombre de charges (sur 3 : taxe foncière, assurance PNO, charges copro
/// non récupérables) dont le cash flow ci-dessus utilise la moyenne réelle
/// des dépenses saisies plutôt que le montant déclaré sur le bien — `0` si
/// cash flow purement prévisionnel (comportement historique), `3` si
/// entièrement basé sur le réel. Permet à l'UI d'expliciter la provenance
/// du chiffre affiché (cf. `ProfitabilitySnapshot.cashflowRealChargesCount`).
///
/// [now] est injectable pour les tests.
int countRealCashflowCharges({
  required int? propertyTaxAnnualCents,
  required int? insurancePnoAnnualCents,
  required int? condoFeesNonRecoverableCents,
  PropertyRealCharges realCharges = PropertyRealCharges.empty,
  DateTime? now,
}) {
  final buckets = _resolveCharges(
    propertyTaxAnnualCents: propertyTaxAnnualCents,
    insurancePnoAnnualCents: insurancePnoAnnualCents,
    condoFeesNonRecoverableCents: condoFeesNonRecoverableCents,
    realCharges: realCharges,
    now: now ?? DateTime.now(),
  );
  return buckets.where((b) => b.isReal).length;
}

// ---------------------------------------------------------------------------
// Résolution réel vs prévisionnel — implémentation interne
// ---------------------------------------------------------------------------

/// Résolution d'une charge : montant annuel effectif à utiliser (réel ou
/// déclaré) + statut (exploitable ? réel ?).
typedef _ChargeBucket = ({bool usable, bool isReal, int annualCents});

List<_ChargeBucket> _resolveCharges({
  required int? propertyTaxAnnualCents,
  required int? insurancePnoAnnualCents,
  required int? condoFeesNonRecoverableCents,
  required PropertyRealCharges realCharges,
  required DateTime now,
}) => [
  _resolveChargeBucket(
    declaredAnnualCents: propertyTaxAnnualCents,
    entries: realCharges.propertyTax,
    now: now,
  ),
  _resolveChargeBucket(
    declaredAnnualCents: insurancePnoAnnualCents,
    entries: realCharges.insurancePno,
    now: now,
  ),
  _resolveChargeBucket(
    declaredAnnualCents: condoFeesNonRecoverableCents,
    entries: realCharges.condoFeesNonRecoverable,
    now: now,
  ),
];

/// Bascule le réel/prévisionnel pour UNE charge — voir la doc de tête de
/// fichier pour la justification de la règle.
///
/// Bascule sur le réel si [entries] contient soit une **récurrence en
/// cours** (bascule immédiate : une périodicité déclarée n'est pas un
/// échantillon), soit une dépense ponctuelle antérieure ou égale au début de
/// la fenêtre glissante de [kRealExpensesRollingWindow] (recul d'au moins un
/// an sur cette charge). Sinon, repli sur [declaredAnnualCents] si
/// renseigné ; sinon la charge n'est pas exploitable.
_ChargeBucket _resolveChargeBucket({
  required int? declaredAnnualCents,
  required List<RealChargeEntry> entries,
  required DateTime now,
}) {
  final windowStart = now.subtract(kRealExpensesRollingWindow);
  final hasActiveRecurrence = entries.any((e) => e.isRecurringActiveAt(now));
  final hasFullYearCoverage = entries.any(
    (e) => !e.expenseDate.isAfter(windowStart),
  );
  if (hasActiveRecurrence || hasFullYearCoverage) {
    final annualCents = entries.fold<int>(
      0,
      (sum, e) =>
          sum + _annualContributionCents(e, windowStart: windowStart, now: now),
    );
    return (usable: true, isReal: true, annualCents: annualCents);
  }
  if (declaredAnnualCents != null) {
    return (usable: true, isReal: false, annualCents: declaredAnnualCents);
  }
  return (usable: false, isReal: false, annualCents: 0);
}

/// Contribution d'UNE entrée à la charge annuelle de son poste.
///
/// - ponctuelle : son montant si elle tombe dans la fenêtre glissante,
///   sinon rien (comportement historique) ;
/// - récurrence **en cours** : son montant annualisé (`montant × échéances
///   par an`) — voir « bascule immédiate » en tête de fichier ;
/// - récurrence **terminée** (ou pas encore commencée) : ses seules
///   échéances réellement tombées dans la fenêtre, comme de l'histoire.
int _annualContributionCents(
  RealChargeEntry entry, {
  required DateTime windowStart,
  required DateTime now,
}) {
  if (!entry.recurrence.isRecurring) {
    final inWindow =
        !entry.expenseDate.isBefore(windowStart) &&
        !entry.expenseDate.isAfter(now);
    return inWindow ? entry.amountCents : 0;
  }
  if (entry.isRecurringActiveAt(now)) {
    return entry.amountCents * entry.recurrence.occurrencesPerYear;
  }
  return entry.amountCents * entry.occurrencesBetween(windowStart, now).length;
}
