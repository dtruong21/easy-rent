/// Filtre de la liste des quittances par statut.
///
/// Utilisé par [receiptStatusFilterProvider] (provider local family par leaseId).
///
/// FEAT-043 (i18n) : cet enum ne porte plus de libellé FR en dur (ancien
/// getter `labelFr`, retiré — zéro référence restante). Le mapping enum →
/// libellé localisé vit dans la couche présentation : voir
/// `ReceiptStatusFilterL10n`
/// (`lib/features/receipts/presentation/widgets/receipt_status_filter_l10n.dart`).
enum ReceiptStatusFilter {
  /// Toutes les quittances (aucun filtre).
  all,

  /// Quittances partagées ([Receipt.hasBeenShared] == true).
  sent,

  /// Quittances payées ([Receipt.paymentIds] non vide, non annulées).
  paid,

  /// Quittances annulées ([Receipt.isVoided] == true).
  voided,
}
