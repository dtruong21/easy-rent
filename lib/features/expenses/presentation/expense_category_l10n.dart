import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/expense_category.dart';

/// Libellé localisé de [ExpenseCategory] (FEAT-043 — pattern « enum métier
/// → mapping l10n en présentation », cf. `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`expense_category.dart`) conserve `label` (FR en dur) pour ne
/// pas casser `test/widget/expense_form_test.dart` (référence directe à ce
/// getter) — même approche que `DocumentCategoryL10n`
/// (`lib/features/documents/presentation/document_category_l10n.dart`).
///
/// Nommée `localizedLabel` (et non `label`) : un membre d'extension portant
/// le même nom qu'un membre d'instance existant (`ExpenseCategory.label`)
/// serait invisible à la résolution statique — Dart préfère toujours le
/// membre de la classe/l'enum.
extension ExpenseCategoryL10n on ExpenseCategory {
  String localizedLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ExpenseCategory.recoverable => l10n.expensesCategoryRecoverable,
      ExpenseCategory.nonRecoverable => l10n.expensesCategoryNonRecoverable,
    };
  }
}
