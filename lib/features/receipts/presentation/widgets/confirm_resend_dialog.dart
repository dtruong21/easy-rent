import 'package:flutter/material.dart';

import '../../../../core/utils/french_date.dart';

/// Dialog de confirmation de renvoi d'une quittance déjà envoyée.
///
/// Affiche la date du dernier envoi et l'adresse email masquée (RGPD).
/// L'utilisateur peut annuler ou confirmer le renvoi.
///
/// Aligné sur [VoidReceiptDialog] pour la structure et les keys.
class ConfirmResendDialog extends StatelessWidget {
  const ConfirmResendDialog({
    super.key,
    required this.previousSentAt,
    required this.previousMaskedEmail,
    required this.onConfirm,
  });

  /// Date du dernier envoi.
  final DateTime previousSentAt;

  /// Adresse email masquée (ex: "j***@example.com").
  final String previousMaskedEmail;

  /// Callback appelé si l'utilisateur confirme le renvoi.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final dateLabel = FrenchDate.format(previousSentAt);

    return AlertDialog(
      key: const Key('dialog_confirm_resend'),
      title: Row(
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('Renvoyer cette quittance ?'),
        ],
      ),
      content: Text(
        'Vous l\'avez déjà envoyée le $dateLabel à $previousMaskedEmail.\n\n'
        'Voulez-vous l\'envoyer à nouveau ?',
      ),
      actions: [
        TextButton(
          key: const Key('btn_resend_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('btn_resend_confirm'),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: const Text('Renvoyer'),
        ),
      ],
    );
  }
}
