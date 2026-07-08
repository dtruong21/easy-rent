import 'package:flutter/widgets.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/charge_regularization_share_error_reason.dart';

/// Traduit un [ChargeRegularizationShareErrorReason] en message localisé
/// (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`charge_regularization_share_error_reason.dart`) reste pur.
/// Même pattern que `ReceiptActionErrorL10n`
/// (`lib/features/receipts/presentation/widgets/receipt_action_error_l10n.dart`).
///
/// [ChargeRegularizationShareErrorReason.unknown] réutilise directement
/// `l10n.commonErrorGeneric` (libellé générique d'état d'erreur, cf.
/// `lib/l10n/l10n_convention.dart` règle 2 — chaîne transverse) plutôt que
/// de dupliquer une clé `chargeRegularizationError...` supplémentaire pour un
/// texte identique.
extension ChargeRegularizationShareErrorReasonL10n
    on ChargeRegularizationShareErrorReason {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ChargeRegularizationShareErrorReason.shareFailed =>
        l10n.chargeRegularizationErrorShareFailed,
      ChargeRegularizationShareErrorReason.unknown => l10n.commonErrorGeneric,
    };
  }
}
