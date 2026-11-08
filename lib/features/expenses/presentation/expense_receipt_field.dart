import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/plan_matrix.g.dart';
import '../../documents/application/upload_documents_controller.dart'
    show kMaxFileSizeBytes;
import '../application/expense_receipt_upload_controller.dart';
import '../domain/expense_receipt_upload_error_reason.dart';
import '../domain/expense_receipt_upload_state.dart';
import 'expense_receipt_upload_error_reason_l10n.dart';

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
///
/// Édition (correctif review FEAT-041, finding 6) : si [existingDocumentId]
/// est fourni (dépense en cours d'édition avec un justificatif déjà attaché,
/// `initial.documentId != null`) et que le bailleur n'a pas encore interagi
/// avec le champ (état [ReceiptIdle]), affiche un état « justificatif déjà
/// attaché » avec les actions Remplacer/Retirer plutôt qu'un simple bouton
/// "Joindre" qui laissait croire, à tort, qu'aucun fichier n'était associé à
/// la dépense. Le `documentId` existant reste conservé à la soumission tant
/// qu'aucun nouvel upload n'a réussi et qu'aucun retrait explicite n'a été
/// demandé — voir [ExpenseReceiptUploadState.removed], consulté par
/// `ExpenseFormPage._submit`.
class ExpenseReceiptField extends ConsumerWidget {
  const ExpenseReceiptField({
    super.key,
    required this.propertyId,
    this.leaseId,
    this.enabled = true,
    this.existingDocumentId,
  });

  /// Bien parent — transmis à `createDocument` comme alternative au bail.
  final String propertyId;

  /// Bail sélectionné dans le formulaire (optionnel), transmis tel quel.
  final String? leaseId;

  final bool enabled;

  /// `documentId` du justificatif déjà attaché à la dépense en édition
  /// (`initial.documentId`), ou `null` en création / dépense sans
  /// justificatif.
  final String? existingDocumentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(expenseReceiptUploadControllerProvider);
    final hasExistingDocument = existingDocumentId != null;
    final maxFileSizeBytes =
        ref.watch(quotaLimitProvider(PlanQuota.documentMaxBytes)) ??
        kMaxFileSizeBytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.expensesReceiptFieldLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.expensesReceiptFieldHelper,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 8),
        switch (state) {
          ReceiptIdle() when hasExistingDocument => _ExistingDocumentRow(
            onReplace: enabled ? () => _pickAndUpload(context, ref) : null,
            onRemove: enabled
                ? () => ref
                      .read(expenseReceiptUploadControllerProvider.notifier)
                      .removeExisting()
                : null,
          ),
          ReceiptIdle() => _PickButton(
            enabled: enabled,
            onPressed: () => _pickAndUpload(context, ref),
          ),
          ReceiptRemoved() => _PickButton(
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
            message: ExpenseReceiptUploadErrorReason.fromCode(
              message,
            ).message(context, maxFileSizeBytes: maxFileSizeBytes),
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

    // Un nouvel upload réussi remplace le justificatif existant — l'état
    // [ReceiptSuccess] qui en résulte prend le pas sur `hasExistingDocument`
    // (le `switch` de [build] ne teste `hasExistingDocument` que pour l'état
    // [ReceiptIdle]).
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
      label: Text(context.l10n.expensesReceiptPickButton),
    );
  }
}

/// État « justificatif déjà attaché » (correctif review FEAT-041, finding 6)
/// — affiché en édition tant que le bailleur n'a ni remplacé ni retiré le
/// justificatif existant. Ne connaît pas le nom du fichier (non chargé
/// depuis `documents` pour rester dans le périmètre `expenses/**`) — le
/// libellé générique suffit à lever l'ambiguïté "aucun justificatif" vs
/// "justificatif déjà présent".
class _ExistingDocumentRow extends StatelessWidget {
  const _ExistingDocumentRow({required this.onReplace, required this.onRemove});

  final VoidCallback? onReplace;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.l10n.expensesReceiptExistingLabel,
            key: const Key('text_expense_receipt_existing'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        TextButton(
          key: const Key('btn_replace_expense_receipt'),
          onPressed: onReplace,
          child: Text(context.l10n.expensesReceiptReplaceButton),
        ),
        IconButton(
          key: const Key('btn_remove_existing_expense_receipt'),
          onPressed: onRemove,
          icon: const Icon(Icons.close),
          tooltip: context.l10n.expensesReceiptRemoveTooltip,
        ),
      ],
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
        Expanded(
          child: Text(context.l10n.expensesReceiptUploadingLabel(filename)),
        ),
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
          tooltip: context.l10n.expensesReceiptRemoveTooltip,
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
          child: Text(context.l10n.commonRetry),
        ),
      ],
    );
  }
}
