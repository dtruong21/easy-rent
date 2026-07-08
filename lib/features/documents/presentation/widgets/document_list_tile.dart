import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../application/delete_document_controller.dart';
import '../../application/update_document_category_controller.dart';
import '../../data/documents_repository.dart';
import '../../domain/document.dart';
import '../../domain/document_category.dart';
import '../delete_document_error_reason_l10n.dart';
import '../update_category_error_reason_l10n.dart';
import 'delete_document_dialog.dart';
import 'document_category_chip.dart';
import 'edit_category_dialog.dart';

final _log = Logger('DocumentListTile');

/// Tile d'un document dans la liste d'un bail.
///
/// Affiche : nom de fichier, icône MIME, chip catégorie, taille, date d'upload.
/// Actions (via PopupMenuButton) :
/// - Télécharger : génère une URL signée et ouvre dans un nouvel onglet.
/// - Modifier la catégorie : ouvre [EditCategoryDialog].
/// - Supprimer : ouvre [DeleteDocumentDialog] (avec variante legal_hold).
class DocumentListTile extends ConsumerWidget {
  const DocumentListTile({
    super.key,
    required this.document,
    required this.leaseId,
  });

  final Document document;
  final String leaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // Écouter le state de suppression
    ref.listen<DeleteDocumentState>(
      deleteDocumentControllerProvider(document.id),
      (_, next) {
        if (!context.mounted) return;
        if (next is DeleteSuccess) {
          final msg = next.hardDeleted
              ? l10n.documentsDeleteSuccessSnackbar
              : l10n.documentsDeleteSuccessLegalHoldSnackbar;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          );
          ref
              .read(deleteDocumentControllerProvider(document.id).notifier)
              .reset();
        } else if (next is DeleteError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.reason.message(context)),
              backgroundColor: theme.colorScheme.errorContainer,
            ),
          );
          ref
              .read(deleteDocumentControllerProvider(document.id).notifier)
              .reset();
        }
      },
    );

    // Écouter le state de mise à jour de catégorie
    ref.listen<UpdateCategoryState>(
      updateDocumentCategoryControllerProvider(document.id),
      (_, next) {
        if (!context.mounted) return;
        if (next is UpdateCategorySuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.documentsCategoryUpdateSuccessSnackbar),
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          );
          ref
              .read(
                updateDocumentCategoryControllerProvider(document.id).notifier,
              )
              .reset();
        } else if (next is UpdateCategoryError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.reason.message(context)),
              backgroundColor: theme.colorScheme.errorContainer,
            ),
          );
          ref
              .read(
                updateDocumentCategoryControllerProvider(document.id).notifier,
              )
              .reset();
        }
      },
    );

    final isDeleting =
        ref.watch(deleteDocumentControllerProvider(document.id))
            is DeleteSubmitting;

    return ListTile(
      key: Key('doc_tile_${document.id}'),
      leading: _MimeIcon(document: document),
      title: Text(
        document.filename,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: _SubtitleRow(document: document),
      trailing: isDeleting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _ActionsMenu(document: document, leaseId: leaseId, ref: ref),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

class _MimeIcon extends StatelessWidget {
  const _MimeIcon({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (document.isPdf) {
      return Icon(
        Icons.picture_as_pdf_outlined,
        color: theme.colorScheme.error,
        size: 28,
      );
    }
    if (document.isImage) {
      return Icon(
        Icons.image_outlined,
        color: theme.colorScheme.primary,
        size: 28,
      );
    }
    return Icon(
      Icons.insert_drive_file_outlined,
      color: theme.colorScheme.onSurfaceVariant,
      size: 28,
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DocumentCategoryChip(category: document.category),
        Text(
          '· ${document.sizeHuman} · ${document.uploadedAtLabel}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (document.legalHold) _LegalHoldBadge(),
      ],
    );
  }
}

class _LegalHoldBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outlined,
            size: 10,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 2),
          Text(
            context.l10n.documentsLegalHoldBadge,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.tertiary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({
    required this.document,
    required this.leaseId,
    required this.ref,
  });

  final Document document;
  final String leaseId;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<_Action>(
      key: Key('doc_menu_${document.id}'),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => _handleAction(context, action),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _Action.download,
          child: Text(l10n.documentsActionDownload),
        ),
        PopupMenuItem(
          value: _Action.editCategory,
          child: Text(l10n.documentsActionEditCategory),
        ),
        PopupMenuItem(value: _Action.delete, child: Text(l10n.commonDelete)),
      ],
    );
  }

  void _handleAction(BuildContext context, _Action action) {
    switch (action) {
      case _Action.download:
        _download(context);
      case _Action.editCategory:
        _editCategory(context);
      case _Action.delete:
        _delete(context);
    }
  }

  Future<void> _download(BuildContext context) async {
    try {
      final url = await ref
          .read(documentsRepositoryProvider)
          .createSignedUrl(document.storagePath);
      final uri = Uri.parse(url);
      if (!context.mounted) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!context.mounted) return;
        _showError(context, context.l10n.documentsDownloadErrorCantOpen);
      }
    } catch (e, st) {
      _log.severe('download failed doc=${document.id}', e, st);
      if (!context.mounted) return;
      _showError(context, context.l10n.documentsDownloadErrorGeneric);
    }
  }

  Future<void> _editCategory(BuildContext context) async {
    final newCat = await showDialog<DocumentCategory>(
      context: context,
      builder: (_) => EditCategoryDialog(currentCategory: document.category),
    );
    if (newCat == null) return;
    ref
        .read(updateDocumentCategoryControllerProvider(document.id).notifier)
        .update(docId: document.id, newCategory: newCat, leaseId: leaseId);
  }

  void _delete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => DeleteDocumentDialog(
        document: document,
        onConfirm: () => ref
            .read(deleteDocumentControllerProvider(document.id).notifier)
            .delete(docId: document.id, leaseId: leaseId),
      ),
    );
  }

  void _showError(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      ),
    );
  }
}

enum _Action { download, editCategory, delete }
