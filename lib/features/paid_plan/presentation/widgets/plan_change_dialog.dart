import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Dialog de confirmation d'un changement de palier en libre-service
/// (FEAT-056 §4.4).
///
/// **Le changement est immédiat et proraté** — jamais un remboursement,
/// jamais un différé de fin de période — l'utilisateur doit en être informé
/// **avant** de confirmer (montée facturée au prorata, descente créditée sur
/// la prochaine facture). Retourne `true` si confirmé, `false`/`null` sinon.
/// Extrait de [ProPricingPage] pour respecter la limite de 200 lignes par
/// widget (CLAUDE.md) — même pattern que `subscription_cancel_dialog.dart`.
Future<bool?> showPlanChangeDialog(
  BuildContext context, {
  required String targetLevelLabel,
  required bool isUpgrade,
}) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('dialog_plan_change'),
      title: Text(l10n.planChangeDialogTitle),
      content: Text(
        isUpgrade
            ? l10n.planChangeUpgradeBody(targetLevelLabel)
            : l10n.planChangeDowngradeBody(targetLevelLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('btn_plan_change_confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.planChangeConfirm),
        ),
      ],
    ),
  );
}
