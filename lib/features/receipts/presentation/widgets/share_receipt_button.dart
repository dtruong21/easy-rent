import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/share_receipt_controller.dart';
import '../../domain/receipt.dart';
import '../../domain/share_receipt_state.dart';
import 'confirm_resend_dialog.dart';

/// Bouton de partage d'une quittance (Web Share API + fallback mailto:).
///
/// Affichage adaptatif selon l'état de la quittance :
/// - Désactivé (gris) si [receipt.isVoided] ou [receipt.isStale].
/// - Désactivé si [tenantEmail] est vide ou null.
/// - Icône [Icons.share_outlined] si jamais partagée.
/// - Icône [Icons.share] si déjà partagée (avec tooltip date).
/// - [CircularProgressIndicator] 18px pendant la préparation.
///
/// Gère les états via [shareReceiptControllerProvider] (autoDispose).
/// Sur succès Web Share API : SnackBar + adresse copiée presse-papier.
/// Sur succès fallback : SnackBar rappelant d'attacher le PDF manuellement.
class ShareReceiptButton extends ConsumerWidget {
  const ShareReceiptButton({
    super.key,
    required this.receipt,
    required this.leaseId,
    required this.tenantFirstName,
    required this.propertyAddress,
    required this.landlordFullName,
    this.tenantEmail,
  });

  final Receipt receipt;
  final String leaseId;

  /// Prénom du locataire (pour le corps du message).
  final String tenantFirstName;

  /// Adresse du logement (pour le corps du message).
  final String propertyAddress;

  /// Nom complet du bailleur (pour la signature du message).
  final String landlordFullName;

  /// Email du locataire — si null ou vide, le bouton est désactivé.
  final String? tenantEmail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shareState = ref.watch(shareReceiptControllerProvider);
    final isPreparing = shareState is ShareReceiptPreparing;
    final isInvalid = receipt.isVoided || receipt.isStale;
    final hasEmail = tenantEmail != null && tenantEmail!.isNotEmpty;
    final theme = Theme.of(context);

    // Listener pour les feedbacks post-transition.
    ref.listen<ShareReceiptState>(shareReceiptControllerProvider, (_, next) {
      if (!context.mounted) return;
      _handleStateChange(context, ref, next, theme);
    });

    if (isPreparing) {
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
        key: Key('btn_share_receipt_disabled_${receipt.id}'),
        icon: Icon(Icons.share_outlined, color: theme.colorScheme.outline),
        tooltip: 'Quittance invalide — partage impossible',
        onPressed: null,
      );
    }

    if (!hasEmail) {
      return IconButton(
        key: Key('btn_share_receipt_no_email_${receipt.id}'),
        icon: Icon(Icons.share_outlined, color: theme.colorScheme.outline),
        tooltip: 'Locataire sans email — partage impossible',
        onPressed: null,
      );
    }

    final icon = receipt.hasBeenShared
        ? Icon(Icons.share, color: theme.colorScheme.primary)
        : const Icon(Icons.share_outlined);

    final tooltip = receipt.hasBeenShared
        ? 'Repartager (déjà partagée le ${receipt.sharedAtLabel})'
        : 'Partager par email';

    return IconButton(
      key: Key('btn_share_receipt_${receipt.id}'),
      icon: icon,
      tooltip: tooltip,
      onPressed: () {
        ref
            .read(shareReceiptControllerProvider.notifier)
            .initiate(
              receipt: receipt,
              leaseId: leaseId,
              tenantEmail: tenantEmail!,
              tenantFirstName: tenantFirstName,
              propertyAddress: propertyAddress,
              landlordFullName: landlordFullName,
            );
      },
    );
  }

  void _handleStateChange(
    BuildContext context,
    WidgetRef ref,
    ShareReceiptState state,
    ThemeData theme,
  ) {
    final notifier = ref.read(shareReceiptControllerProvider.notifier);

    switch (state) {
      case ShareReceiptConfirmingResend():
        _showConfirmDialog(context, ref, state);

      case ShareReceiptShared(:final usedNativeShare):
        final message = usedNativeShare
            ? 'Quittance partagée. Adresse du locataire copiée dans le presse-papier.'
            : 'PDF téléchargé. Pensez à l\'attacher manuellement à votre email.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        notifier.reset();

      case ShareReceiptTenantNoEmail():
        // L'état tenantNoEmail est géré via le bouton désactivé — pas de SnackBar
        // supplémentaire nécessaire ici (le bouton ne devrait pas être cliquable).
        notifier.reset();

      case ShareReceiptError():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.message),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
        notifier.reset();

      case ShareReceiptIdle():
      case ShareReceiptPreparing():
        break;
    }
  }

  Future<void> _showConfirmDialog(
    BuildContext context,
    WidgetRef ref,
    ShareReceiptConfirmingResend state,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => ConfirmResendDialog(
        previousSentAt: state.previousSharedAt,
        previousMaskedEmail: state.previousMaskedEmail,
        onConfirm: () {
          ref
              .read(shareReceiptControllerProvider.notifier)
              .confirmResend(
                receipt: receipt,
                leaseId: leaseId,
                tenantEmail: tenantEmail ?? '',
                tenantFirstName: tenantFirstName,
                propertyAddress: propertyAddress,
                landlordFullName: landlordFullName,
              );
        },
      ),
    );
    // Si l'utilisateur annule (pop sans confirmer), on remet idle.
    if (ref.read(shareReceiptControllerProvider)
        is ShareReceiptConfirmingResend) {
      ref.read(shareReceiptControllerProvider.notifier).reset();
    }
  }
}
