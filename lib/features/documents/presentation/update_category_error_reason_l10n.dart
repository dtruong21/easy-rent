import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../application/update_document_category_controller.dart';

/// Traduit un [UpdateCategoryErrorReason] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) —
/// [UpdateDocumentCategoryController] (application) reste pur. Voir
/// `lib/l10n/l10n_convention.dart` pour le pattern complet (identique à
/// `ValidationErrorL10n`/`ProfileFormErrorReasonL10n`).
extension UpdateCategoryErrorReasonL10n on UpdateCategoryErrorReason {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      UpdateCategoryErrorReason.connectionError =>
        l10n.documentsErrorConnection,
      UpdateCategoryErrorReason.unexpected =>
        l10n.documentsCategoryUpdateErrorUnexpected,
    };
  }
}
