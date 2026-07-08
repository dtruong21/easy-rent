import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/receipt_status_filter.dart';

/// Libellé localisé de [ReceiptStatusFilter] (FEAT-043 — pattern « enum
/// métier → mapping l10n en présentation », cf. `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`receipt_status_filter.dart`) reste un enum nu, sans
/// dépendance à `AppLocalizations`/`BuildContext` — l'ancien `labelFr` (FR
/// en dur) a été supprimé (zéro référence restante hors de cette extension,
/// FEAT-043 sweep final) ; toute l'UI utilise désormais [label].
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
