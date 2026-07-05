import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

import '../application/expense_receipt_upload_controller.dart';
import '../domain/expense_receipt_upload_state.dart';

final _log = Logger('ExpenseReceiptField');

/// Champ d'upload du justificatif (facture, décompte syndic) dans le
/// formulaire dépense.
///
/// **Recommandé, non bloquant** (décision produit #8,
/// `docs/plans/FEAT-041-depenses.md` § g) : l'utilisateur peut créer une
/// dépense sans joindre de fichier. En cas d'échec d'upload, le formulaire
/// reste soumettable (le libellé invite simplement à réessayer).
///
/// Réutilise le pipeline d'upload de la feature `documents` (Storage →
/// Callable `createDocument` v2) via [ExpenseReceiptUploadController].
class ExpenseReceiptField extends ConsumerWidget {
  const ExpenseReceiptField({
    super.key,
    required this.propertyId,
    this.leaseId,
    this.enabled = true,
  });

  /// Bien parent — transmis à `createDocument` comme alternative au bail.
  final String propertyId;

  /// Bail sélectionné dans le formulaire (optionnel), transmis tel quel.
  final String? leaseId;

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(expenseReceiptUploadControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Justificatif (recommandé)',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Facture ou décompte syndic — conservé 5 à 10 ans (preuve locative '
          'et comptable). Vous pouvez créer la dépense sans justificatif.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 8),
        switch (state) {
          ReceiptIdle() => _PickButton(
            enabled: enabled,
            onPressed: () => _pickAndUpload(context, ref),
          ),
          ReceiptUploading(:final filename, :final progress) => _UploadingRow(
            filename: filename,
            progress: progress,
          ),
          ReceiptSuccess(:final filename) => _SuccessRow(
            filename: filename,
            onRemove: enabled
                ? () => ref
                      .read(expenseReceiptUploadControllerProvider.notifier)
                      .reset()
                : null,
          ),
          ReceiptError(:final filename, :final message) => _ErrorRow(
            filename: filename,
            message: message,
            onRetry: enabled ? () => _pickAndUpload(context, ref) : null,
          ),
        },
      ],
    );
  }

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    if (file.bytes == null || file.name.isEmpty) {
      _log.warning('skipping receipt ${file.name}: bytes null');
      return;
    }

    await ref
        .read(expenseReceiptUploadControllerProvider.notifier)
        .upload(
          propertyId: propertyId,
          leaseId: leaseId,
          filename: file.name,
          bytes: file.bytes!,
          mimeType: lookupMimeType(file.name) ?? 'application/octet-stream',
        );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('btn_pick_expense_receipt'),
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.attach_file_outlined),
      label: const Text('Joindre un justificatif'),
    );
  }
}

class _UploadingRow extends StatelessWidget {
  const _UploadingRow({required this.filename, required this.progress});

  final String filename;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, value: progress),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text('Envoi de $filename…')),
      ],
    );
  }
}

class _SuccessRow extends StatelessWidget {
  const _SuccessRow({required this.filename, required this.onRemove});

  final String filename;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(filename, overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
        IconButton(
          key: const Key('btn_remove_expense_receipt'),
          onPressed: onRemove,
          icon: const Icon(Icons.close),
          tooltip: 'Retirer le justificatif',
        ),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({
    required this.filename,
    required this.message,
    required this.onRetry,
  });

  final String filename;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: theme.colorScheme.error),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
        TextButton(
          key: const Key('btn_retry_expense_receipt'),
          onPressed: onRetry,
          child: const Text('Réessayer'),
        ),
      ],
    );
  }
}
