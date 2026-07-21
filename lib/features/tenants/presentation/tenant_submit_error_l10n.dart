import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/tenant_submit_error.dart';

/// Traduit un [TenantSubmitError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`tenant_submit_error.dart`) reste pur. Même pattern que
/// `ValidationErrorL10n` (`lib/core/validation/validation_error_l10n.dart`).
extension TenantSubmitErrorL10n on TenantSubmitError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      TenantSubmitError.hasActiveLeases => l10n.tenantsErrorHasActiveLeases,
      TenantSubmitError.limitReached => l10n.tenantsErrorLimitReached,
      TenantSubmitError.permissionDenied => l10n.tenantsErrorPermissionDenied,
      TenantSubmitError.serviceUnavailable =>
        l10n.tenantsErrorServiceUnavailable,
      TenantSubmitError.notFound => l10n.tenantsErrorNotFound,
      TenantSubmitError.saveFailed => l10n.tenantsErrorSaveFailed,
      TenantSubmitError.unknown => l10n.tenantsErrorUnknown,
    };
  }
}
