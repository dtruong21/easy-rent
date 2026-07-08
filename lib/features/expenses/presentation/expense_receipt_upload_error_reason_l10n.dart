import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/expense_receipt_upload_error_reason.dart';

/// Traduit un [ExpenseReceiptUploadErrorReason] en message localisé
/// (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`expense_receipt_upload_error_reason.dart`) reste pur. Même
/// pattern que `UploadFileErrorReasonL10n`
/// (`lib/features/documents/presentation/upload_file_error_reason_l10n.dart`).
extension ExpenseReceiptUploadErrorReasonL10n
    on ExpenseReceiptUploadErrorReason {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ExpenseReceiptUploadErrorReason.fileTooLarge =>
        l10n.expensesReceiptErrorFileTooLarge,
      ExpenseReceiptUploadErrorReason.unsupportedFormat =>
        l10n.expensesReceiptErrorUnsupportedFormat,
      ExpenseReceiptUploadErrorReason.storageError =>
        l10n.expensesReceiptErrorStorage,
      ExpenseReceiptUploadErrorReason.connectionError =>
        l10n.expensesReceiptErrorConnection,
      ExpenseReceiptUploadErrorReason.unexpected =>
        l10n.expensesReceiptErrorUnexpected,
    };
  }
}
