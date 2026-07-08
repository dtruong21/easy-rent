import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/tenant_filter.dart';

/// Libellé localisé de [TenantFilter] (FEAT-043 — pattern « enum métier →
/// mapping l10n en présentation », cf. `lib/l10n/l10n_convention.dart`).
///
/// Le domaine (`tenant_filter.dart`) reste un enum nu, sans dépendance à
/// `AppLocalizations`/`BuildContext`.
extension TenantFilterL10n on TenantFilter {
  String label(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      TenantFilter.all => l10n.tenantsFilterAll,
      TenantFilter.withActiveLease => l10n.tenantsFilterActive,
      TenantFilter.withoutActiveLease => l10n.tenantsFilterWithoutLease,
    };
  }
}
