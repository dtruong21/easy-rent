import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/expense_nature.dart';

/// Libellé et justification localisés de [ExpenseNature] (FEAT-043 —
/// pattern « enum métier → mapping l10n en présentation », cf.
/// `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`expense_nature.dart`) conserve `label`/
/// `lockOrWarningExplanation` (FR en dur) pour ne pas casser
/// `test/widget/expense_form_test.dart` (référence directe à ces getters) —
/// même approche que `DocumentCategoryL10n`.
///
/// Nommés `localizedLabel`/`localizedLockOrWarningExplanation` (et non
/// `label`/`lockOrWarningExplanation`) : un membre d'extension portant le
/// même nom qu'un membre d'instance existant serait invisible à la
/// résolution statique — Dart préfère toujours le membre de la classe/l'enum.
extension ExpenseNatureL10n on ExpenseNature {
  String localizedLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ExpenseNature.condoCharges => l10n.expensesNatureCondoCharges,
      ExpenseNature.propertyTax => l10n.expensesNaturePropertyTax,
      ExpenseNature.insurancePno => l10n.expensesNatureInsurancePno,
      ExpenseNature.managementFees => l10n.expensesNatureManagementFees,
      ExpenseNature.works => l10n.expensesNatureWorks,
      ExpenseNature.repairMaintenance => l10n.expensesNatureRepairMaintenance,
      ExpenseNature.other => l10n.expensesNatureOther,
    };
  }

  /// Justification affichée à titre d'aide contextuelle (verrouillage dur ou
  /// avertissement d'ajustement) — voir [ExpenseNature.lockOrWarningExplanation].
  String localizedLockOrWarningExplanation(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ExpenseNature.condoCharges => l10n.expensesNatureExplanationCondoCharges,
      ExpenseNature.propertyTax => l10n.expensesNatureExplanationPropertyTax,
      ExpenseNature.insurancePno => l10n.expensesNatureExplanationInsurancePno,
      ExpenseNature.managementFees =>
        l10n.expensesNatureExplanationManagementFees,
      ExpenseNature.works => l10n.expensesNatureExplanationWorks,
      ExpenseNature.repairMaintenance =>
        l10n.expensesNatureExplanationRepairMaintenance,
      ExpenseNature.other => l10n.expensesNatureExplanationOther,
    };
  }
}
