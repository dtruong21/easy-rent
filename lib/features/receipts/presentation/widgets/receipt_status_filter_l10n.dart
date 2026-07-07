import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/receipt_status_filter.dart';

/// Libellé localisé de [ReceiptStatusFilter] (FEAT-043 — pattern « enum
/// métier → mapping l10n en présentation », cf. `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`receipt_status_filter.dart`) conserve `labelFr` (FR en dur)
/// par cohérence avec `LeaseType.labelFr`/`DocumentType.label` (évite toute
/// régression si un test unitaire pur venait à l'exercer directement) —
/// cette extension est la voie recommandée pour tout nouveau code
/// présentation.
extension ReceiptStatusFilterL10n on ReceiptStatusFilter {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ReceiptStatusFilter.all => l10n.receiptsFilterAll,
      ReceiptStatusFilter.sent => l10n.receiptsFilterSent,
      ReceiptStatusFilter.paid => l10n.receiptsFilterPaid,
      ReceiptStatusFilter.voided => l10n.receiptsFilterVoided,
    };
  }
}
