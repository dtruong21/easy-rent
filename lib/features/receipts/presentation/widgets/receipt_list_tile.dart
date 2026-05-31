import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/void_receipt_controller.dart';
import '../../data/receipts_repository.dart';
import '../../domain/receipt.dart';
import 'void_receipt_dialog.dart';

final _log = Logger('ReceiptListTile');

/// Tile d'une quittance dans la liste de la fiche bail.
///
/// Affiche : période, type (Quittance / Reçu), montant total.
/// Badges : "Annulée" si [isVoided], "Périmée" si [isStale].
/// Actions :
/// - Bouton télécharger : génère une URL signée et ouvre le PDF.
/// - Bouton voider : ouvre [VoidReceiptDialog] (masqué si déjà voided).
class ReceiptListTile extends ConsumerWidget {
  const ReceiptListTile({
    super.key,
    required this.receipt,
    required this.leaseId,
  });

  final Receipt receipt;
  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final voidState = ref.watch(voidReceiptControllerProvider);
    final isVoiding = voidState is VoidReceiptSubmitting;

    // Écouter le state pour les feedbacks.
    ref.listen<VoidReceiptState>(voidReceiptControllerProvider, (_, next) {
      if (!context.mounted) return;
      if (next is VoidReceiptSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Quittance annulée'),
            backgroundColor: theme.colorScheme.primaryContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider.notifier).reset();
      } else if (next is VoidReceiptError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
        ref.read(voidReceiptControllerProvider.notifier).reset();
      }
    });

    return ListTile(
      key: Key('receipt_tile_${receipt.id}'),
      title: _buildTitle(context, theme),
      subtitle: _buildSubtitle(theme),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('btn_download_receipt_${receipt.id}'),
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Télécharger le PDF',
            onPressed: () => _downloadPdf(context, ref),
          ),
          if (!receipt.isVoided)
            IconButton(
              key: Key('btn_void_receipt_${receipt.id}'),
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Annuler la quittance',
              color: theme.colorScheme.error,
              onPressed: isVoiding ? null : () => _showVoidDialog(context, ref),
            ),
        ],
      ),
    );
  }

  Widget _buildTitle(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Text(receipt.periodLabel, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: 8),
        if (receipt.isVoided) _Badge(label: 'Annulée', isError: true),
        if (receipt.isStale && !receipt.isVoided)
          _Badge(label: 'Périmée', isError: false),
      ],
    );
  }

  Widget _buildSubtitle(ThemeData theme) {
    return Text(
      '${receipt.documentType.label} · ${receipt.totalEuros}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Future<void> _downloadPdf(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(receiptsRepositoryProvider);
      final url = await repo.signedUrl(receipt.pdfPath);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Impossible d\'ouvrir le PDF. Vérifiez votre navigateur.',
              ),
            ),
          );
        }
      }
    } catch (e, st) {
      _log.warning('Erreur lors du téléchargement du PDF', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Impossible de générer le lien de téléchargement.',
            ),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }

  Future<void> _showVoidDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => VoidReceiptDialog(
        onConfirm: (reason) {
          Navigator.of(context).pop();
          ref
              .read(voidReceiptControllerProvider.notifier)
              .voidReceipt(
                receiptId: receipt.id,
                reason: reason,
                leaseId: leaseId,
              );
        },
      ),
    );
  }
}

/// Badge coloré affiché sur la tile.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.isError});

  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final fg = isError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}
