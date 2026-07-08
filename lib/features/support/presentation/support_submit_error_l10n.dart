import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../domain/support_submit_error.dart';

/// Traduit un [SupportSubmitError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`support_submit_error.dart`) reste pur. Même pattern que
/// `TenantSubmitErrorL10n`
/// (`lib/features/tenants/presentation/tenant_submit_error_l10n.dart`).
extension SupportSubmitErrorL10n on SupportSubmitError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      SupportSubmitError.subjectRequired =>
        l10n.supportFormSubjectRequiredError,
      SupportSubmitError.subjectTooLong => l10n.supportFormSubjectTooLongError(
        kSupportSubjectMaxLength,
      ),
      SupportSubmitError.messageRequired =>
        l10n.supportFormMessageRequiredError,
      SupportSubmitError.messageTooLong => l10n.supportFormMessageTooLongError(
        kSupportMessageMaxLength,
      ),
      SupportSubmitError.sendFailed => l10n.supportFormSendFailedError,
    };
  }
}
