import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/send_receipt_controller.dart';
import '../../domain/receipt.dart';
import '../../domain/send_receipt_state.dart';
import 'confirm_resend_dialog.dart';

/// Bouton d'envoi d'une quittance par email.
///
/// Affichage adaptatif selon l'état de la quittance :
/// - Désactivé (gris) si [receipt.isVoided] ou [receipt.isStale].
/// - Icône [Icons.mail_outline] si jamais envoyée.
/// - Icône [Icons.mark_email_read_outlined] si déjà envoyée (avec tooltip date).
/// - [CircularProgressIndicator] pendant l'envoi.
///
/// Gère les états via [sendReceiptControllerProvider] (autoDispose).
/// Sur succès : SnackBar + invalidation du cache [leaseReceiptsProvider].
/// Sur erreur tenant_no_email : SnackBar avec action "Modifier" → /tenants/:id/edit.
/// Sur rateLimited : SnackBar avec durée longue.
class SendReceiptButton extends ConsumerWidget {
  const SendReceiptButton({
    super.key,
    required this.receipt,
    required this.leaseId,
    this.tenantId,
  });

  final Receipt receipt;
  final String leaseId;

  /// Identifiant du locataire — requis pour la navigation "Modifier la fiche".
  /// Si null, l'action SnackBar "Modifier" est omise.
  final String? tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sendState = ref.watch(sendReceiptControllerProvider);
    final isSubmitting = sendState is SendReceiptSubmitting;
    final isInvalid = receipt.isVoided || receipt.isStale;
    final theme = Theme.of(context);

    // Listener pour les feedbacks post-transition.
    ref.listen<SendReceiptState>(sendReceiptControllerProvider, (_, next) {
      if (!context.mounted) return;
      _handleStateChange(context, ref, next, theme);
    });

    if (isSubmitting) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (isInvalid) {
      return IconButton(
        key: Key('btn_send_receipt_disabled_${receipt.id}'),
        icon: Icon(Icons.mail_outline, color: theme.colorScheme.outline),
        tooltip: 'Quittance invalide — envoi impossible',
        onPressed: null,
      );
    }

    final icon = receipt.hasBeenSent
        ? Icon(Icons.mark_email_read_outlined, color: theme.colorScheme.primary)
        : const Icon(Icons.mail_outline);

    final tooltip = receipt.hasBeenSent
        ? 'Renvoyer (envoyé le ${receipt.sentAtLabel})'
        : 'Envoyer par email';

    return IconButton(
      key: Key('btn_send_receipt_${receipt.id}'),
      icon: icon,
      tooltip: tooltip,
      onPressed: () {
        ref
            .read(sendReceiptControllerProvider.notifier)
            .initiate(receipt: receipt, leaseId: leaseId);
      },
    );
  }

  void _handleStateChange(
    BuildContext context,
    WidgetRef ref,
    SendReceiptState state,
    ThemeData theme,
  ) {
    final notifier = ref.read(sendReceiptControllerProvider.notifier);

    switch (state) {
      case SendReceiptConfirmingResend():
        _showConfirmDialog(context, ref, state);

      case SendReceiptSuccess():
        final masked =
            receipt.maskedSentToEmail ??
            (state.sentToEmail.isNotEmpty ? state.sentToEmail : '…');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quittance envoyée à $masked'),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        notifier.reset();

      case SendReceiptTenantNoEmail():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Ajoutez l\'adresse email du locataire dans sa fiche'
              ' pour activer l\'envoi.',
            ),
            backgroundColor: theme.colorScheme.errorContainer,
            action: tenantId != null
                ? SnackBarAction(
                    label: 'Modifier',
                    onPressed: () => context.go('/tenants/$tenantId/edit'),
                  )
                : null,
            duration: const Duration(seconds: 6),
          ),
        );
        notifier.reset();

      case SendReceiptRateLimited():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Quota d\'envoi dépassé. Réessayez le mois prochain.',
            ),
            backgroundColor: theme.colorScheme.errorContainer,
            duration: const Duration(seconds: 6),
          ),
        );
        notifier.reset();

      case SendReceiptError():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.message),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
        notifier.reset();

      case SendReceiptIdle():
      case SendReceiptSubmitting():
        break;
    }
  }

  Future<void> _showConfirmDialog(
    BuildContext context,
    WidgetRef ref,
    SendReceiptConfirmingResend state,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => ConfirmResendDialog(
        previousSentAt: state.previousSentAt,
        previousMaskedEmail: state.previousMaskedEmail,
        onConfirm: () {
          ref
              .read(sendReceiptControllerProvider.notifier)
              .confirmResend(receipt: receipt, leaseId: leaseId);
        },
      ),
    );
    // Si l'utilisateur annule (pop sans confirmer), on remet idle.
    if (ref.read(sendReceiptControllerProvider)
        is SendReceiptConfirmingResend) {
      ref.read(sendReceiptControllerProvider.notifier).reset();
    }
  }
}
