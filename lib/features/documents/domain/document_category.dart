import 'package:flutter/material.dart';

/// Catégorie d'un document attaché à un bail et/ou à un bien.
///
/// Mappé sur le champ `category` de la collection Firestore `documents`.
/// Pattern aligné [DocumentType] (FEAT-007).
///
/// [expenseReceipt] (FEAT-041b) : justificatif de dépense (facture, décompte
/// syndic) — sous `legalHold` dès la création (rétention 5-10 ans, voir
/// `docs/plans/FEAT-041-depenses.md` § g).
enum DocumentCategory {
  bailSigne,
  etatDesLieux,
  attestationAssurance,
  quittanceScannee,
  expenseReceipt,
  autre;

  /// Valeur attendue par la Cloud Function / stockée sur le document Firestore.
  String get sqlValue => switch (this) {
    DocumentCategory.bailSigne => 'bail_signe',
    DocumentCategory.etatDesLieux => 'etat_des_lieux',
    DocumentCategory.attestationAssurance => 'attestation_assurance',
    DocumentCategory.quittanceScannee => 'quittance_scannee',
    DocumentCategory.expenseReceipt => 'expense_receipt',
    DocumentCategory.autre => 'autre',
  };

  /// Libellé FR pour l'affichage dans l'UI.
  ///
  /// FEAT-043 (i18n) : conservé en dur pour ne pas casser
  /// `test/unit/document_category_test.dart` (test unitaire pur, sans
  /// `BuildContext`) — mêmes raisons que `LeaseType.labelFr`, voir
  /// `lib/features/leases/domain/lease_type.dart`. Le nouveau code
  /// présentation doit utiliser `DocumentCategoryL10n.localizedLabel`
  /// (`lib/features/documents/presentation/document_category_l10n.dart`).
  String get label => switch (this) {
    DocumentCategory.bailSigne => 'Bail signé',
    DocumentCategory.etatDesLieux => 'État des lieux',
    DocumentCategory.attestationAssurance => "Attestation d'assurance",
    DocumentCategory.quittanceScannee => 'Quittance scannée',
    DocumentCategory.expenseReceipt => 'Justificatif de dépense',
    DocumentCategory.autre => 'Autre',
  };

  /// Icône Material associée à la catégorie.
  IconData get icon => switch (this) {
    DocumentCategory.bailSigne => Icons.description_outlined,
    DocumentCategory.etatDesLieux => Icons.home_work_outlined,
    DocumentCategory.attestationAssurance => Icons.shield_outlined,
    DocumentCategory.quittanceScannee => Icons.receipt_outlined,
    DocumentCategory.expenseReceipt => Icons.receipt_long_outlined,
    DocumentCategory.autre => Icons.folder_outlined,
  };

  /// Vrai si la catégorie entraîne un `legalHold` automatique (calculé côté
  /// serveur par la Callable `createDocument`, `LEGAL_HOLD_CATEGORIES`).
  ///
  /// Utilisé côté UI pour afficher les avertissements de suppression.
  bool get requiresLegalHold =>
      this == DocumentCategory.bailSigne ||
      this == DocumentCategory.etatDesLieux ||
      this == DocumentCategory.expenseReceipt;

  /// Parse la valeur serveur en [DocumentCategory].
  ///
  /// Lance [ArgumentError] si la valeur est inconnue.
  static DocumentCategory fromSql(String value) => switch (value) {
    'bail_signe' => DocumentCategory.bailSigne,
    'etat_des_lieux' => DocumentCategory.etatDesLieux,
    'attestation_assurance' => DocumentCategory.attestationAssurance,
    'quittance_scannee' => DocumentCategory.quittanceScannee,
    'expense_receipt' => DocumentCategory.expenseReceipt,
    'autre' => DocumentCategory.autre,
    _ => throw ArgumentError('DocumentCategory inconnue : $value'),
  };
}
