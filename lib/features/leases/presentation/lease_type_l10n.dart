import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/lease_type.dart';

/// Libellé et texte d'aide localisés de [LeaseType] (FEAT-043 — pattern
/// « enum métier → mapping l10n en présentation », cf.
/// `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`lease_type.dart`) conserve `labelFr`/`formHelperText` pour ne
/// pas casser les call sites non encore migrés hors périmètre de ce ticket
/// (aucun identifié dans `lib/features/leases/**`) — cette extension est la
/// voie recommandée pour tout nouveau code présentation dans ce module.
extension LeaseTypeL10n on LeaseType {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      LeaseType.unfurnished => l10n.leasesTypeUnfurnished,
      LeaseType.furnished => l10n.leasesTypeFurnished,
      LeaseType.mobility => l10n.leasesTypeMobility,
      LeaseType.student => l10n.leasesTypeStudent,
    };
  }

  /// Texte indicatif affiché sous le champ "Type de bail" dans le formulaire.
  String formHelperText(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      LeaseType.unfurnished => l10n.leasesTypeUnfurnishedHelper,
      LeaseType.furnished => l10n.leasesTypeFurnishedHelper,
      LeaseType.mobility => l10n.leasesTypeMobilityHelper,
      LeaseType.student => l10n.leasesTypeStudentHelper,
    };
  }
}
