/// Sens du solde d'une régularisation annuelle de charges (FEAT-029 V1.2).
///
/// Le solde n'est jamais persisté — c'est une valeur calculée à la volée,
/// affichée à l'écran et reportée sur le PDF « Avis de régularisation des
/// charges ». Le sens (à réclamer / à rembourser / équilibré) porte la
/// sémantique légale : voir `docs/backlog/029-charges-regularisation.md`,
/// section « Legal / compliance notes ».
enum ChargeRegularizationBalanceDirection {
  /// Dépenses réelles > provisions encaissées : le bailleur doit réclamer
  /// un complément au locataire.
  dueByTenant,

  /// Dépenses réelles < provisions encaissées : le bailleur doit rembourser
  /// le trop-perçu au locataire.
  dueToTenant,

  /// Dépenses réelles == provisions encaissées : aucun mouvement financier.
  balanced;

  /// Libellé français explicite affiché à l'écran et sur le PDF.
  ///
  /// Volontairement redondant ("à réclamer AU locataire" / "à rembourser AU
  /// locataire") pour éviter toute ambiguïté de sens — cf. Gherkin FEAT-029 :
  /// « un libellé clair indique si le solde est "à réclamer au locataire"
  /// (positif) ou "à rembourser au locataire" (négatif) ».
  String get labelFr => switch (this) {
    ChargeRegularizationBalanceDirection.dueByTenant =>
      'à réclamer au locataire',
    ChargeRegularizationBalanceDirection.dueToTenant =>
      'à rembourser au locataire',
    ChargeRegularizationBalanceDirection.balanced => 'aucun solde',
  };
}

/// Résultat calculé d'une régularisation annuelle de charges.
///
/// Objet de calcul pur — jamais persisté en base (V1 : « le solde calculé
/// est affiché à l'utilisateur mais l'encaissement/remboursement réel reste
/// un paiement classique », cf. backlog FEAT-029). Sert uniquement à piloter
/// l'affichage écran et le contenu du PDF généré.
///
/// ⚠️ Ne mélange QUE les charges récupérables (`payments.chargesAmountCents`,
/// lui-même pré-rempli depuis `leases.chargesAmountCents` = la part
/// récupérable du bail — FEAT-036).
///
/// **Deux notions distinctes de « non récupérable » coexistent dans le
/// projet, aucune n'entre dans ce solde** (FEAT-036) :
/// - `leases.nonRecoverableChargesCents` : ventilation des charges DU BAIL
///   (saisie sur le formulaire bail, affichée sur la fiche bail). Distinct
///   du récupérable (`leases.chargesAmountCents`), jamais sommé ici.
/// - `properties.condoFeesNonRecoverableCents` : charges de copropriété non
///   récupérables DU BIEN (rentabilité bailleur, simulateur), sans lien avec
///   un bail précis.
///
/// Mélanger l'une ou l'autre dans ce calcul exposerait à une sur-facturation
/// illégale au locataire (décret 87-713) — la régularisation ne doit régler
/// que le récupérable réellement encaissé via les provisions du bail.
class ChargeRegularizationBalance {
  const ChargeRegularizationBalance({
    required this.periodStart,
    required this.periodEnd,
    required this.provisionsCollectedCents,
    required this.actualExpensesCents,
  });

  /// Début de la période de référence (inclus).
  final DateTime periodStart;

  /// Fin de la période de référence (inclus).
  final DateTime periodEnd;

  /// Total des provisions de charges encaissées sur la période — somme des
  /// `payments.chargesAmountCents` dont la période de paiement recouvre la
  /// période de référence (calcul : [ChargeProvisionsCalculator]).
  final int provisionsCollectedCents;

  /// Total des dépenses réelles justifiées par le syndic, saisi manuellement
  /// par le bailleur depuis son décompte.
  final int actualExpensesCents;

  /// Solde signé en centimes : dépenses réelles − provisions encaissées.
  ///
  /// Positif = complément dû par le locataire. Négatif = trop-perçu à
  /// rembourser. Zéro = équilibré.
  int get balanceCents => actualExpensesCents - provisionsCollectedCents;

  /// Valeur absolue du solde, toujours positive — utile pour l'affichage
  /// monétaire (le signe est porté par [direction]/[labelFr], jamais par le
  /// montant affiché).
  int get balanceAbsCents => balanceCents.abs();

  /// Sens du solde (à réclamer / à rembourser / équilibré).
  ChargeRegularizationBalanceDirection get direction {
    if (balanceCents > 0) {
      return ChargeRegularizationBalanceDirection.dueByTenant;
    }
    if (balanceCents < 0) {
      return ChargeRegularizationBalanceDirection.dueToTenant;
    }
    return ChargeRegularizationBalanceDirection.balanced;
  }

  /// Libellé français explicite, ex. "à réclamer au locataire".
  String get labelFr => direction.labelFr;
}
