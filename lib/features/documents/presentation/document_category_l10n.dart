import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/document_category.dart';

/// Libellé localisé de [DocumentCategory] (FEAT-043 — pattern « enum métier
/// → mapping l10n en présentation », cf. `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`document_category.dart`) conserve `label` (FR en dur) pour ne
/// pas casser `test/unit/document_category_test.dart` (test unitaire pur,
/// sans `BuildContext`) — même approche que `LeaseTypeL10n`. Cette extension
/// est la voie recommandée pour tout nouveau code présentation dans ce
/// module.
///
/// Nommée `localizedLabel` (et non `label`) : un membre d'extension portant
/// le même nom qu'un membre d'instance existant (`DocumentCategory.label`)
/// serait invisible à la résolution statique — Dart préfère toujours le
/// membre de la classe/l'enum.
extension DocumentCategoryL10n on DocumentCategory {
  String localizedLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      DocumentCategory.bailSigne => l10n.documentsCategoryBailSigne,
      DocumentCategory.etatDesLieux => l10n.documentsCategoryEtatDesLieux,
      DocumentCategory.attestationAssurance =>
        l10n.documentsCategoryAttestationAssurance,
      DocumentCategory.quittanceScannee =>
        l10n.documentsCategoryQuittanceScannee,
      DocumentCategory.expenseReceipt => l10n.documentsCategoryExpenseReceipt,
      DocumentCategory.autre => l10n.documentsCategoryAutre,
    };
  }
}
