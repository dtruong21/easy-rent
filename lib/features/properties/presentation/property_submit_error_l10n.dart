import 'package:flutter/widgets.dart';

import '../../../core/config/store_billing.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../domain/property_submit_error.dart';

/// Traduit un [PropertySubmitError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`property_submit_error.dart`) reste pur. Même pattern que
/// `TenantSubmitErrorL10n`/`LeaseSubmitErrorL10n`.
extension PropertySubmitErrorL10n on PropertySubmitError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      PropertySubmitError.notFound => l10n.propertiesErrorNotFound,
      PropertySubmitError.hasActiveLeases =>
        l10n.propertiesErrorHasActiveLeases,
      PropertySubmitError.limitReached =>
        isStoreApp
            ? l10n.propertiesErrorLimitReachedStore
            : l10n.propertiesErrorLimitReached,
      PropertySubmitError.permissionDenied =>
        l10n.propertiesErrorPermissionDenied,
      PropertySubmitError.serviceUnavailable =>
        l10n.propertiesErrorServiceUnavailable,
      PropertySubmitError.connectionError =>
        l10n.propertiesErrorConnectionError,
      PropertySubmitError.saveFailed => l10n.propertiesErrorSaveFailed,
      PropertySubmitError.unknown => l10n.commonErrorGeneric,
    };
  }
}
