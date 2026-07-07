import 'package:flutter/material.dart';

import 'expense_category.dart';

/// Nature d'une dépense — liste fermée alignée sur le décret n°87-713.
///
/// **Réplique fidèle** de la table `NATURE_DEFAULT_CATEGORY` côté Cloud
/// Function (`functions/src/callable/expenses.ts`) — voir
/// `docs/plans/FEAT-041-depenses.md` § a). La dérivation de [ExpenseCategory]
/// reste **serveur** (garde-fou juridique non contournable) ; cet enum ne
/// sert qu'à présélectionner la catégorie côté UI et à savoir si un
/// ajustement (override) doit afficher un avertissement ou être bloqué en
/// dur.
enum ExpenseNature {
  /// Charges de copropriété (syndic) — récupérable par défaut.
  condoCharges,

  /// Taxe foncière — jamais récupérable (verrouillé).
  propertyTax,

  /// Assurance propriétaire non-occupant — jamais récupérable (verrouillé).
  insurancePno,

  /// Honoraires de gestion locative — jamais récupérables (verrouillé).
  managementFees,

  /// Travaux — mixte selon nature exacte (art. 606 non-récup / entretien récup).
  works,

  /// Réparation / entretien — mixte selon le décret.
  repairMaintenance,

  /// Fourre-tout conservateur (dont assurance GLI en V1).
  other;

  /// Valeur attendue par la Cloud Function / stockée sur le document Firestore.
  String get sqlValue => switch (this) {
    ExpenseNature.condoCharges => 'condo_charges',
    ExpenseNature.propertyTax => 'property_tax',
    ExpenseNature.insurancePno => 'insurance_pno',
    ExpenseNature.managementFees => 'management_fees',
    ExpenseNature.works => 'works',
    ExpenseNature.repairMaintenance => 'repair_maintenance',
    ExpenseNature.other => 'other',
  };

  /// Libellé FR pour l'affichage dans l'UI.
  ///
  /// FEAT-043 (i18n) : conservé en dur pour ne pas casser
  /// `test/widget/expense_form_test.dart` (référence directe à ce getter,
  /// hors périmètre de ce ticket) — même approche que `DocumentCategory.label`
  /// (`lib/features/documents/domain/document_category.dart`). Le nouveau
  /// code présentation doit utiliser `ExpenseNatureL10n.localizedLabel`
  /// (`lib/features/expenses/presentation/expense_nature_l10n.dart`).
  String get label => switch (this) {
    ExpenseNature.condoCharges => 'Charges de copropriété (syndic)',
    ExpenseNature.propertyTax => 'Taxe foncière',
    ExpenseNature.insurancePno => 'Assurance propriétaire non-occupant',
    ExpenseNature.managementFees => 'Honoraires de gestion locative',
    ExpenseNature.works => 'Travaux',
    ExpenseNature.repairMaintenance => 'Réparation / entretien',
    ExpenseNature.other => 'Autre',
  };

  /// Icône Material associée à la nature.
  IconData get icon => switch (this) {
    ExpenseNature.condoCharges => Icons.apartment_outlined,
    ExpenseNature.propertyTax => Icons.account_balance_outlined,
    ExpenseNature.insurancePno => Icons.shield_outlined,
    ExpenseNature.managementFees => Icons.support_agent_outlined,
    ExpenseNature.works => Icons.construction_outlined,
    ExpenseNature.repairMaintenance => Icons.build_outlined,
    ExpenseNature.other => Icons.receipt_long_outlined,
  };

  /// Catégorie par défaut appliquée par la Cloud Function si le client ne
  /// force pas de catégorie — réplique de `NATURE_DEFAULT_CATEGORY`.
  ExpenseCategory get defaultCategory => switch (this) {
    ExpenseNature.condoCharges => ExpenseCategory.recoverable,
    ExpenseNature.propertyTax => ExpenseCategory.nonRecoverable,
    ExpenseNature.insurancePno => ExpenseCategory.nonRecoverable,
    ExpenseNature.managementFees => ExpenseCategory.nonRecoverable,
    ExpenseNature.works => ExpenseCategory.nonRecoverable,
    ExpenseNature.repairMaintenance => ExpenseCategory.nonRecoverable,
    ExpenseNature.other => ExpenseCategory.nonRecoverable,
  };

  /// Vrai si la catégorie est **verrouillée** pour cette nature (override
  /// interdit — la Cloud Function renvoie `failed-precondition
  /// category_locked_for_nature` si le client tente de la forcer).
  bool get isCategoryLocked => switch (this) {
    ExpenseNature.propertyTax => true,
    ExpenseNature.insurancePno => true,
    ExpenseNature.managementFees => true,
    ExpenseNature.condoCharges => false,
    ExpenseNature.works => false,
    ExpenseNature.repairMaintenance => false,
    ExpenseNature.other => false,
  };

  /// Justification FR affichée à titre d'aide contextuelle (verrouillage ou
  /// avertissement d'ajustement).
  ///
  /// FEAT-043 (i18n) : conservé en dur (voir note sur [label]). Le nouveau
  /// code présentation doit utiliser
  /// `ExpenseNatureL10n.localizedLockOrWarningExplanation`.
  String get lockOrWarningExplanation => switch (this) {
    ExpenseNature.propertyTax =>
      'La taxe foncière n\'est jamais récupérable auprès du locataire.',
    ExpenseNature.insurancePno =>
      'L\'assurance propriétaire non-occupant n\'est jamais récupérable.',
    ExpenseNature.managementFees =>
      'Les honoraires de gestion locative ne sont jamais récupérables.',
    ExpenseNature.condoCharges =>
      'Certaines lignes du décompte syndic peuvent être non récupérables '
          '(grosses réparations, art. 606).',
    ExpenseNature.works =>
      'Les travaux d\'amélioration ne sont pas récupérables ; seul le petit '
          'entretien peut l\'être — vérifiez le détail de la facture.',
    ExpenseNature.repairMaintenance =>
      'Le classement récupérable/non-récupérable dépend du détail exact des '
          'travaux réalisés (décret n°87-713).',
    ExpenseNature.other =>
      'Vérifiez la nature exacte de la dépense avant de la classer '
          'récupérable.',
  };

  /// Construit une [ExpenseNature] depuis sa valeur serveur.
  ///
  /// Retourne [other] par défaut si la valeur est inconnue — tolérance
  /// défensive pour des données futures (nouvelle nature ajoutée côté CF
  /// avant le déploiement du client).
  static ExpenseNature fromSql(String value) => switch (value) {
    'condo_charges' => ExpenseNature.condoCharges,
    'property_tax' => ExpenseNature.propertyTax,
    'insurance_pno' => ExpenseNature.insurancePno,
    'management_fees' => ExpenseNature.managementFees,
    'works' => ExpenseNature.works,
    'repair_maintenance' => ExpenseNature.repairMaintenance,
    'other' => ExpenseNature.other,
    _ => ExpenseNature.other,
  };
}
