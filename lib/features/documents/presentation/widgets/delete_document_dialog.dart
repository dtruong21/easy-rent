import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/document.dart';

/// Dialog de confirmation de suppression d'un document.
///
/// Deux variantes selon [Document.legalHold] :
/// - legal_hold ON  → titre "Document conservé (obligation légale)" +
///                    mention loi 1989 art. 21 / RGPD 5 ans + bouton "Masquer"
/// - legal_hold OFF → titre "Supprimer ce document ?" +
///                    avertissement irréversible + bouton "Supprimer"
class DeleteDocumentDialog extends StatelessWidget {
  const DeleteDocumentDialog({
    super.key,
    required this.document,
    required this.onConfirm,
  });

  final Document document;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    if (document.legalHold) {
      return AlertDialog(
        key: const Key('delete_doc_legal_hold_dialog'),
        title: Row(
          children: [
            Icon(
              Icons.lock_outlined,
              size: 20,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.documentsDeleteLegalHoldDialogTitle)),
          ],
        ),
        content: Text(l10n.documentsDeleteLegalHoldDialogContent),
        actions: [
          TextButton(
            key: const Key('btn_cancel_delete'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('btn_confirm_delete'),
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: Text(l10n.documentsDeleteHideButton),
          ),
        ],
      );
    }

    return AlertDialog(
      key: const Key('delete_doc_dialog'),
      title: Text(l10n.documentsDeleteDialogTitle),
      content: Text(l10n.documentsDeleteDialogContent(document.filename)),
      actions: [
        TextButton(
          key: const Key('btn_cancel_delete'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('btn_confirm_delete'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }
}
