import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/edl_enums.dart';

/// Traduit un [EdlCondition] en libellé localisé (FEAT-037).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine ([EdlCondition]) reste indépendant de la locale d'affichage. Patron
/// `UpdateCategoryErrorReasonL10n`
/// (`lib/features/documents/presentation/update_category_error_reason_l10n.dart`).
extension EdlConditionL10n on EdlCondition {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      EdlCondition.neuf => l10n.edlConditionNeuf,
      EdlCondition.bon => l10n.edlConditionBon,
      EdlCondition.moyen => l10n.edlConditionMoyen,
      EdlCondition.mauvais => l10n.edlConditionMauvais,
    };
  }
}
