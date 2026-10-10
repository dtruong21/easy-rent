import 'package:flutter/widgets.dart';

import '../../../core/config/store_billing.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../domain/lease_submit_error.dart';

/// Traduit un [LeaseSubmitError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`lease_submit_error.dart`) reste pur. Même pattern que
/// `TenantSubmitErrorL10n`/`PaymentSubmitErrorL10n`.
extension LeaseSubmitErrorL10n on LeaseSubmitError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      LeaseSubmitError.notFound => l10n.leasesErrorNotFound,
      LeaseSubmitError.alreadyClosed => l10n.leasesErrorAlreadyClosed,
      LeaseSubmitError.propertyOrTenantNotOwned =>
        l10n.leasesErrorPropertyOrTenantNotOwned,
      LeaseSubmitError.propertyOrTenantArchived =>
        l10n.leasesErrorPropertyOrTenantArchived,
      LeaseSubmitError.permissionDenied => l10n.leasesErrorPermissionDenied,
      LeaseSubmitError.invalidState => l10n.leasesErrorInvalidState,
      LeaseSubmitError.serviceUnavailable => l10n.leasesErrorServiceUnavailable,
      LeaseSubmitError.limitReached =>
        canOfferUpgrade
            ? l10n.leasesErrorLimitReached
            : l10n.leasesErrorLimitReachedStore,
      LeaseSubmitError.saveFailed => l10n.leasesErrorSaveFailed,
      LeaseSubmitError.unknown => l10n.commonErrorGeneric,
    };
  }
}
