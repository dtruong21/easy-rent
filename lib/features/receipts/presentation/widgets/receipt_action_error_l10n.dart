import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/receipt_action_error.dart';

/// Traduit un [ReceiptActionError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`receipt_action_error.dart`) reste pur. Même pattern que
/// `TenantSubmitErrorL10n`
/// (`lib/features/tenants/presentation/tenant_submit_error_l10n.dart`).
extension ReceiptActionErrorL10n on ReceiptActionError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ReceiptActionError.permissionDenied => l10n.receiptsErrorPermissionDenied,
      ReceiptActionError.noPaymentForPeriod =>
        l10n.receiptsErrorNoPaymentForPeriod,
      ReceiptActionError.leaseOrPaymentsNotFound =>
        l10n.receiptsErrorLeaseOrPaymentsNotFound,
      ReceiptActionError.generationFailed => l10n.receiptsErrorGenerationFailed,
      ReceiptActionError.receiptNotFound => l10n.receiptsErrorReceiptNotFound,
      ReceiptActionError.alreadyVoidedOrInvalid =>
        l10n.receiptsErrorAlreadyVoidedOrInvalid,
      ReceiptActionError.voidFailed => l10n.receiptsErrorVoidFailed,
      ReceiptActionError.shareFailed => l10n.receiptsErrorShareFailed,
      ReceiptActionError.unknown => l10n.receiptsErrorUnknown,
    };
  }
}
