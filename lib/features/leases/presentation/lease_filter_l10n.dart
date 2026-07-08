import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/lease_filter.dart';

/// Libellé localisé de [LeaseFilter] (FEAT-043 — exemple pilote du pattern
/// « enum métier → mapping l10n en présentation », cf.
/// `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`lease_filter.dart`) reste un enum nu, sans dépendance à
/// `AppLocalizations`/`BuildContext`.
extension LeaseFilterL10n on LeaseFilter {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      LeaseFilter.all => l10n.leasesFilterAll,
      LeaseFilter.active => l10n.leasesFilterActive,
      LeaseFilter.renewable => l10n.leasesFilterRenewable,
      LeaseFilter.late => l10n.leasesFilterLate,
      LeaseFilter.terminated => l10n.leasesFilterTerminated,
    };
  }
}
