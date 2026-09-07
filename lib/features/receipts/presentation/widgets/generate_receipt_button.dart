import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../application/generate_receipt_controller.dart';
import '../../domain/receipt_action_error.dart';
import '../../domain/receipt_generation_state.dart';
import 'profile_incomplete_dialog.dart';
import 'receipt_action_error_l10n.dart';
import 'receipt_preview_dialog.dart';

final _log = Logger('GenerateReceiptButton');

/// Bouton "Générer une quittance" réutilisable.
///
/// Invoque [GenerateReceiptController.submitFromPayment] et gère les états :
/// - [submitting] : affiche un CircularProgressIndicator dans le bouton.
/// - [success] : ouvre [ReceiptPreviewDialog].
/// - [profileIncomplete] : ouvre [ProfileIncompleteDialog].
/// - [error] : affiche un SnackBar erreur.
///
/// Utilisé depuis [PaymentListTile] (action "Générer une quittance").
class GenerateReceiptButton extends ConsumerWidget {
  const GenerateReceiptButton({
    super.key,
    required this.paymentId,
    required this.leaseId,
  });

  final String paymentId;
  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(generateReceiptControllerProvider(paymentId));
    final isSubmitting = state.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );

    ref.listen<ReceiptGenerationState>(
      generateReceiptControllerProvider(paymentId),
      (_, next) {
        if (!context.mounted) return;
        next.whenOrNull(
          success: (result) {
            showDialog<void>(
              context: context,
              builder: (_) => ReceiptPreviewDialog(result: result),
            ).then((_) {
              if (context.mounted) {
                ref
                    .read(generateReceiptControllerProvider(paymentId).notifier)
                    .reset();
              }
            });
          },
          profileIncomplete: (missing) {
            showDialog<void>(
              context: context,
              builder: (_) => ProfileIncompleteDialog(missing: missing),
            ).then((_) {
              if (context.mounted) {
                ref
                    .read(generateReceiptControllerProvider(paymentId).notifier)
                    .reset();
              }
            });
          },
          error: (message) {
            _log.warning('generate receipt error: $message');
            final errorMessage = ReceiptActionError.fromCode(
              message,
            ).message(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
              ),
            );
            ref
                .read(generateReceiptControllerProvider(paymentId).notifier)
                .reset();
          },
        );
      },
    );

    return IconButton(
      key: Key('btn_generate_receipt_$paymentId'),
      icon: isSubmitting
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.receipt_long_outlined),
      tooltip: context.l10n.receiptsGenerateButtonTooltip,
      onPressed: isSubmitting
          ? null
          : () => ref
                .read(generateReceiptControllerProvider(paymentId).notifier)
                .submitFromPayment(paymentId: paymentId, leaseId: leaseId),
    );
  }
}
