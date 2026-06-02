import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

import '../../../../core/utils/byte_format.dart';
import '../../application/documents_quota_provider.dart';
import '../../application/upload_documents_controller.dart';
import '../../domain/document_category.dart';
import '../../domain/documents_quota.dart';
import '../../domain/upload_documents_state.dart';
import 'edit_category_dialog.dart';
import 'upload_progress_list.dart';

final _log = Logger('UploadDocumentsDropZone');

/// Zone d'upload de documents.
///
/// Affiche :
/// - Un bouton "Sélectionner des fichiers" qui ouvre le picker multi-fichiers.
/// - Une zone DragTarget pour le drag & drop Web (note : le DragTarget Flutter
///   natif ne capture pas les fichiers OS sur Web — workaround : picker uniquement
///   pour le MVP, drag&drop natif reporté en P1 selon §11 Q3 du plan).
/// - La progression par fichier pendant l'upload.
/// - Le quota utilisé (et un warning si > 100 Mo).
class UploadDocumentsDropZone extends ConsumerWidget {
  const UploadDocumentsDropZone({super.key, required this.leaseId});

  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadState = ref.watch(uploadDocumentsControllerProvider);
    final asyncQuota = ref.watch(documentsQuotaProvider);

    final uploading = uploadState is Uploading ? uploadState : null;
    final completed = uploadState is UploadCompleted ? uploadState : null;
    final isUploading = uploading != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zone visuelle drag & drop (bouton toujours visible)
        _DropZoneArea(
          isUploading: isUploading,
          onPickFiles: () => _pickFiles(context, ref),
        ),

        // Liste de progression pendant / après upload
        if (uploading != null || completed != null) ...[
          const SizedBox(height: 8),
          UploadProgressList(
            files: uploading?.files ?? completed?.files ?? const [],
          ),
        ],

        // Récap après complétion
        if (completed != null) ...[
          const SizedBox(height: 8),
          _CompletionSummary(
            state: completed,
            onDismiss: () =>
                ref.read(uploadDocumentsControllerProvider.notifier).reset(),
          ),
        ],

        // Quota utilisé
        const SizedBox(height: 8),
        asyncQuota.when(
          loading: () => const SizedBox.shrink(),
          error: (e, st) => const SizedBox.shrink(),
          data: (quota) => _QuotaIndicator(quota: quota),
        ),
      ],
    );
  }

  Future<void> _pickFiles(BuildContext context, WidgetRef ref) async {
    // Vérifier le quota avant de laisser l'utilisateur choisir les fichiers
    final quota = ref.read(documentsQuotaProvider).valueOrNull;
    if (quota != null && quota.isOverSoftLimit) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Vous avez dépassé 100 Mo d\'espace de stockage. '
            'Pensez à supprimer les documents obsolètes.',
          ),
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        ),
      );
      // Warning non-bloquant — on laisse quand même continuer
    }

    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    // Limiter à 10 fichiers par batch (cf. §11 Q4)
    final files = result.files;
    if (files.length > kMaxFilesPerBatch) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum $kMaxFilesPerBatch fichiers à la fois. '
            'Recommencez en plusieurs lots.',
          ),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
      return;
    }

    // Dialog catégorie unique pour le batch
    if (!context.mounted) return;
    final category = await showDialog<DocumentCategory>(
      context: context,
      builder: (_) =>
          const EditCategoryDialog(currentCategory: DocumentCategory.autre),
    );

    if (category == null) return;

    // Construire la liste PickedFile
    final picked = <PickedFile>[];
    for (final f in files) {
      if (f.bytes == null || f.name.isEmpty) {
        _log.warning('skipping file ${f.name}: bytes null');
        continue;
      }
      picked.add(
        PickedFile(
          filename: f.name,
          bytes: f.bytes!,
          mimeType: lookupMimeType(f.name) ?? 'application/octet-stream',
          sizeBytes: f.size,
        ),
      );
    }

    if (picked.isEmpty) return;

    await ref
        .read(uploadDocumentsControllerProvider.notifier)
        .uploadFiles(
          leaseId: leaseId,
          pickedFiles: picked,
          defaultCategory: category,
        );
  }
}

class _DropZoneArea extends StatelessWidget {
  const _DropZoneArea({required this.isUploading, required this.onPickFiles});

  final bool isUploading;
  final VoidCallback onPickFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            'Cliquez pour sélectionner vos fichiers',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            'PDF, JPG, PNG, WEBP · Max 10 Mo par fichier · Max 10 fichiers',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const Key('btn_pick_files'),
            onPressed: isUploading ? null : onPickFiles,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Sélectionner des fichiers'),
          ),
        ],
      ),
    );
  }
}

class _CompletionSummary extends StatelessWidget {
  const _CompletionSummary({required this.state, required this.onDismiss});

  final UploadCompleted state;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = state.failureCount > 0
        ? '${state.successCount} document${state.successCount > 1 ? 's' : ''} ajouté${state.successCount > 1 ? 's' : ''} '
              '(${state.failureCount} échec${state.failureCount > 1 ? 's' : ''})'
        : '${state.successCount} document${state.successCount > 1 ? 's' : ''} ajouté${state.successCount > 1 ? 's' : ''}';

    return Row(
      children: [
        Expanded(
          child: Text(
            msg,
            style: theme.textTheme.bodySmall?.copyWith(
              color: state.failureCount > 0
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
        ),
        TextButton(onPressed: onDismiss, child: const Text('OK')),
      ],
    );
  }
}

class _QuotaIndicator extends StatelessWidget {
  const _QuotaIndicator({required this.quota});

  final DocumentsQuota quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = ByteFormat.format(quota.totalBytes);
    final limit = ByteFormat.format(quota.softLimitBytes);
    final isOver = quota.isOverSoftLimit;

    return Text(
      'Espace utilisé : $used / $limit',
      style: theme.textTheme.bodySmall?.copyWith(
        color: isOver ? theme.colorScheme.error : theme.colorScheme.outline,
      ),
    );
  }
}
