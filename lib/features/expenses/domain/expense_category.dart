import 'package:flutter/material.dart';

/// Catégorie récupérable / non-récupérable d'une dépense (décret n°87-713 du
/// 26 août 1987).
///
/// **Dérivée côté serveur** (Cloud Function `createExpense`/`updateExpense`)
/// à partir de [ExpenseNature] — le client ne fait que présélectionner et
/// afficher un avertissement en cas d'ajustement (`categoryOverridden`).
/// Voir `docs/plans/FEAT-041-depenses.md` § a).
enum ExpenseCategory {
  /// Charge récupérable auprès du locataire (ex. entretien parties communes).
  recoverable,

  /// Charge non-récupérable, à la charge exclusive du bailleur.
  nonRecoverable;

  /// Valeur attendue par la Cloud Function / stockée sur le document Firestore.
  String get sqlValue => switch (this) {
    ExpenseCategory.recoverable => 'recoverable',
    ExpenseCategory.nonRecoverable => 'non_recoverable',
  };

  /// Libellé FR pour l'affichage dans l'UI.
  String get label => switch (this) {
    ExpenseCategory.recoverable => 'Récupérable',
    ExpenseCategory.nonRecoverable => 'Non récupérable',
  };

  /// Couleur de la puce (chip) associée à la catégorie.
  Color chipColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (this) {
      ExpenseCategory.recoverable => Colors.teal.shade700,
      ExpenseCategory.nonRecoverable => colors.error,
    };
  }

  /// Parse la valeur serveur en [ExpenseCategory].
  ///
  /// Retourne [nonRecoverable] par défaut si la valeur est inconnue —
  /// tolérance défensive conservative (décret 87-713 : mieux vaut
  /// sous-classer que sur-facturer le locataire par erreur).
  static ExpenseCategory fromSql(String value) => switch (value) {
    'recoverable' => ExpenseCategory.recoverable,
    'non_recoverable' => ExpenseCategory.nonRecoverable,
    _ => ExpenseCategory.nonRecoverable,
  };
}
