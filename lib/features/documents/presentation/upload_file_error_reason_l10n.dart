import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/upload_file_status.dart';

/// Traduit un [UploadFileErrorReason] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) —
/// [UploadDocumentsController] (application) reste pur. Voir
/// `lib/l10n/l10n_convention.dart` pour le pattern complet (identique à
/// `ValidationErrorL10n`/`ProfileFormErrorReasonL10n`).
extension UploadFileErrorReasonL10n on UploadFileErrorReason {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      UploadFileErrorReason.fileTooLarge =>
        l10n.documentsUploadErrorFileTooLarge,
      UploadFileErrorReason.unsupportedFormat =>
        l10n.documentsUploadErrorUnsupportedFormat,
      UploadFileErrorReason.storageError => l10n.documentsUploadErrorStorage,
      UploadFileErrorReason.connectionError => l10n.documentsErrorConnection,
      UploadFileErrorReason.unexpected => l10n.documentsUploadErrorUnexpected,
    };
  }
}
