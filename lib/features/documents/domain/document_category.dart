import 'package:flutter/material.dart';

/// Catégorie d'un document attaché à un bail.
///
/// Mappé sur l'enum SQL `document_category` (public + dev).
/// Pattern aligné [DocumentType] (FEAT-007).
enum DocumentCategory {
  bailSigne,
  etatDesLieux,
  attestationAssurance,
  quittanceScannee,
  autre;

  /// Valeur SQL telle qu'attendue par Postgres.
  String get sqlValue => switch (this) {
    DocumentCategory.bailSigne => 'bail_signe',
    DocumentCategory.etatDesLieux => 'etat_des_lieux',
    DocumentCategory.attestationAssurance => 'attestation_assurance',
    DocumentCategory.quittanceScannee => 'quittance_scannee',
    DocumentCategory.autre => 'autre',
  };

  /// Libellé FR pour l'affichage dans l'UI.
  String get label => switch (this) {
    DocumentCategory.bailSigne => 'Bail signé',
    DocumentCategory.etatDesLieux => 'État des lieux',
    DocumentCategory.attestationAssurance => "Attestation d'assurance",
    DocumentCategory.quittanceScannee => 'Quittance scannée',
    DocumentCategory.autre => 'Autre',
  };

  /// Icône Material associée à la catégorie.
  IconData get icon => switch (this) {
    DocumentCategory.bailSigne => Icons.description_outlined,
    DocumentCategory.etatDesLieux => Icons.home_work_outlined,
    DocumentCategory.attestationAssurance => Icons.shield_outlined,
    DocumentCategory.quittanceScannee => Icons.receipt_outlined,
    DocumentCategory.autre => Icons.folder_outlined,
  };

  /// Vrai si la catégorie entraîne un [legal_hold] automatique (calculé par
  /// le trigger DB `tr_00b_compute_legal_hold`).
  ///
  /// Utilisé côté UI pour afficher les avertissements de suppression.
  bool get requiresLegalHold =>
      this == DocumentCategory.bailSigne ||
      this == DocumentCategory.etatDesLieux;

  /// Parse la valeur SQL en [DocumentCategory].
  ///
  /// Lance [ArgumentError] si la valeur est inconnue.
  static DocumentCategory fromSql(String value) => switch (value) {
    'bail_signe' => DocumentCategory.bailSigne,
    'etat_des_lieux' => DocumentCategory.etatDesLieux,
    'attestation_assurance' => DocumentCategory.attestationAssurance,
    'quittance_scannee' => DocumentCategory.quittanceScannee,
    'autre' => DocumentCategory.autre,
    _ => throw ArgumentError('DocumentCategory inconnue : $value'),
  };
}
