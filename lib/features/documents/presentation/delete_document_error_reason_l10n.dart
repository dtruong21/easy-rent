import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../application/delete_document_controller.dart';

/// Traduit un [DeleteDocumentErrorReason] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) —
/// [DeleteDocumentController] (application) reste pur. Voir
/// `lib/l10n/l10n_convention.dart` pour le pattern complet (identique à
/// `ValidationErrorL10n`/`ProfileFormErrorReasonL10n`).
extension DeleteDocumentErrorReasonL10n on DeleteDocumentErrorReason {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      DeleteDocumentErrorReason.connectionError =>
        l10n.documentsErrorConnection,
      DeleteDocumentErrorReason.unexpected =>
        l10n.documentsDeleteErrorUnexpected,
    };
  }
}
