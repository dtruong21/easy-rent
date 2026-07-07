import 'package:freezed_annotation/freezed_annotation.dart';

import 'expense.dart';
import 'expense_category.dart';
import 'expense_nature.dart';

part 'expense_filter.freezed.dart';

/// Filtre appliqué à l'historique des dépenses d'un bien
/// ([PropertyExpensesPage]).
///
/// Combine un filtre d'exercice ([periodYear]), de catégorie et de nature.
/// `null` sur un champ = "tous" pour ce critère (pas de restriction).
@freezed
class ExpenseFilter with _$ExpenseFilter {
  const factory ExpenseFilter({
    int? periodYear,
    ExpenseCategory? category,
    ExpenseNature? nature,
  }) = _ExpenseFilter;

  const ExpenseFilter._();

  /// Filtre neutre — aucune restriction.
  static const ExpenseFilter empty = ExpenseFilter();

  /// Vrai si au moins un critère est actif.
  bool get isActive => periodYear != null || category != null || nature != null;

  /// Applique ce filtre à une liste de dépenses (logique pure, testable).
  List<Expense> apply(Iterable<Expense> expenses) {
    return expenses.where((e) {
      if (periodYear != null && e.periodYear != periodYear) return false;
      if (category != null && e.category != category) return false;
      if (nature != null && e.nature != nature) return false;
      return true;
    }).toList();
  }
}
