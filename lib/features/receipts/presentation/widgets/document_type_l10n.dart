import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/document_type.dart';

/// Libellé localisé de [DocumentType] (FEAT-043 — pattern « enum métier →
/// mapping l10n en présentation », cf. `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`document_type.dart`) conserve `label` (FR en dur) pour ne
/// pas casser `test/unit/document_type_test.dart` (test unitaire pur, sans
/// `BuildContext`) — mêmes raisons que `LeaseType.labelFr`
/// (`lib/features/leases/domain/lease_type.dart`) et
/// `DocumentCategory.label` (`lib/features/documents/domain/document_category.dart`).
/// Cette extension est la voie recommandée pour tout nouveau code
/// présentation.
extension DocumentTypeL10n on DocumentType {
  String localizedLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      DocumentType.quittance => l10n.receiptsDocumentTypeQuittance,
      DocumentType.recu => l10n.receiptsDocumentTypeRecu,
    };
  }
}
