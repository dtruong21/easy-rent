import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/french_date.dart';

/// Dialog de confirmation de repartage d'une quittance déjà partagée.
///
/// Affiche la date du dernier partage et l'adresse email masquée (RGPD).
/// L'utilisateur peut annuler ou confirmer le repartage.
///
/// Aligné sur [VoidReceiptDialog] pour la structure et les keys.
class ConfirmResendDialog extends StatelessWidget {
  const ConfirmResendDialog({
    super.key,
    required this.previousSentAt,
    required this.previousMaskedEmail,
    required this.onConfirm,
  });

  /// Date du dernier partage.
  final DateTime previousSentAt;

  /// Adresse email masquée (ex: "j***@example.com").
  final String previousMaskedEmail;

  /// Callback appelé si l'utilisateur confirme le repartage.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final dateLabel = FrenchDate.format(previousSentAt);
    final l10n = context.l10n;

    return AlertDialog(
      key: const Key('dialog_confirm_resend'),
      title: Row(
        children: [
          Icon(
            Icons.share_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.receiptsResendDialogTitle)),
        ],
      ),
      content: Text(
        l10n.receiptsResendDialogContent(dateLabel, previousMaskedEmail),
      ),
      actions: [
        TextButton(
          key: const Key('btn_resend_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('btn_resend_confirm'),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: Text(l10n.receiptsResendConfirmButton),
        ),
      ],
    );
  }
}
