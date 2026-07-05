/// Filtre de la liste des quittances par statut.
///
/// Utilisé par [receiptStatusFilterProvider] (provider local family par leaseId).
enum ReceiptStatusFilter {
  /// Toutes les quittances (aucun filtre).
  all,

  /// Quittances partagées ([Receipt.hasBeenShared] == true).
  sent,

  /// Quittances payées ([Receipt.paymentIds] non vide, non annulées).
  paid,

  /// Quittances annulées ([Receipt.isVoided] == true).
  voided;

  /// Libellé affiché dans l'UI française.
  String get labelFr => switch (this) {
    ReceiptStatusFilter.all => 'Toutes',
    ReceiptStatusFilter.sent => 'Envoyées',
    ReceiptStatusFilter.paid => 'Payées',
    ReceiptStatusFilter.voided => 'Annulées',
  };
}
