import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/payment_submit_error.dart';

/// Traduit un [PaymentSubmitError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`payment_submit_error.dart`) reste pur. Même pattern que
/// `TenantSubmitErrorL10n`/`ExpenseSubmitErrorL10n`.
extension PaymentSubmitErrorL10n on PaymentSubmitError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      PaymentSubmitError.notFound => l10n.paymentsErrorNotFound,
      PaymentSubmitError.permissionDenied => l10n.paymentsErrorPermissionDenied,
      PaymentSubmitError.invalidState => l10n.paymentsErrorInvalidState,
      PaymentSubmitError.serviceUnavailable =>
        l10n.paymentsErrorServiceUnavailable,
      PaymentSubmitError.saveFailed => l10n.paymentsErrorSaveFailed,
      PaymentSubmitError.unknown => l10n.commonErrorGeneric,
    };
  }
}
