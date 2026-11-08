import 'package:flutter/widgets.dart';

import '../../../core/finance/expense_recurrence.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/utils/french_date.dart';

/// Libellés localisés de [ExpenseRecurrence] (FEAT-041d — pattern « enum
/// métier → mapping l10n en présentation », cf.
/// `lib/l10n/l10n_convention.dart` et `expense_nature_l10n.dart`).
///
/// Le domaine (`core/finance/expense_recurrence.dart`) reste pur : aucun
/// libellé, aucune dépendance Flutter.
extension ExpenseRecurrenceL10n on ExpenseRecurrence {
  /// Libellé du sélecteur de périodicité (« Ponctuelle », « Tous les
  /// trimestres »...).
  String localizedLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ExpenseRecurrence.none => l10n.expensesRecurrenceNone,
      ExpenseRecurrence.monthly => l10n.expensesRecurrenceMonthly,
      ExpenseRecurrence.quarterly => l10n.expensesRecurrenceQuarterly,
      ExpenseRecurrence.yearly => l10n.expensesRecurrenceYearly,
    };
  }

  /// Texte du badge affiché sur la ligne de dépense — précise la date de fin
  /// quand il y en a une, pour qu'une récurrence bornée se distingue d'une
  /// récurrence ouverte sans avoir à ouvrir la fiche.
  ///
  /// Retourne `null` pour [ExpenseRecurrence.none] : une dépense ponctuelle
  /// n'affiche aucun badge (c'est le cas nominal, il ne mérite pas de bruit).
  String? localizedBadge(BuildContext context, {DateTime? endDate}) {
    if (!isRecurring) return null;
    final label = localizedLabel(context);
    if (endDate == null) return label;
    return context.l10n.expensesRecurrenceBadgeUntil(
      label,
      FrenchDate.format(endDate),
    );
  }
}
