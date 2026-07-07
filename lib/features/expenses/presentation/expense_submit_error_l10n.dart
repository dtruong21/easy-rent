import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/expense_submit_error.dart';

/// Traduit un [ExpenseSubmitError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`expense_submit_error.dart`) reste pur. Même pattern que
/// `TenantSubmitErrorL10n`/`ReceiptActionErrorL10n`.
extension ExpenseSubmitErrorL10n on ExpenseSubmitError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ExpenseSubmitError.categoryLockedForNature =>
        l10n.expensesErrorCategoryLockedForNature,
      ExpenseSubmitError.permissionDenied => l10n.expensesErrorPermissionDenied,
      ExpenseSubmitError.invalidFields => l10n.expensesErrorInvalidFields,
      ExpenseSubmitError.serviceUnavailable =>
        l10n.expensesErrorServiceUnavailable,
      ExpenseSubmitError.notFound => l10n.expensesErrorNotFound,
      ExpenseSubmitError.saveFailed => l10n.expensesErrorSaveFailed,
      ExpenseSubmitError.unknown => l10n.expensesErrorUnknown,
    };
  }
}
