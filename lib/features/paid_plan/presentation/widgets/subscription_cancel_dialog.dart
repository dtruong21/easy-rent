import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Dialog de confirmation de résiliation (FEAT-044f, art. L215-1-1 —
/// récapitulatif obligatoire avant confirmation).
///
/// Énonce le palier concerné ([levelLabel], FEAT-056 — « Pro »/« Max »/
/// « Ultra »), la date de fin d'accès ([dateLabel], déjà formatée
/// DD/MM/YYYY), le passage automatique en formule Gratuite, et l'absence de
/// remboursement au prorata (choix produit = fin de période, cf. plan
/// FEAT-044f §7). Retourne `true` si l'utilisateur confirme, `false`/`null`
/// sinon (annulé ou dismissed) — extrait de [SubscriptionSection] pour
/// respecter la limite de 200 lignes par widget (CLAUDE.md).
Future<bool?> showSubscriptionCancelDialog(
  BuildContext context, {
  required String dateLabel,
  required String levelLabel,
}) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('dialog_subscription_cancel'),
      title: Text(l10n.subscriptionCancelDialogTitle),
      content: Text(l10n.subscriptionCancelDialogBody(levelLabel, dateLabel)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('btn_subscription_cancel_confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.subscriptionCancelConfirm),
        ),
      ],
    ),
  );
}
