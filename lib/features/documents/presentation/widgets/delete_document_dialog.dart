import 'package:flutter/material.dart';

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
            const Expanded(
              child: Text('Document conservé (obligation légale)'),
            ),
          ],
        ),
        content: const Text(
          'Ce document sera masqué de votre liste mais conservé en archive '
          '(loi du 6 juillet 1989 art. 21 / RGPD — durée de conservation 5 ans).',
        ),
        actions: [
          TextButton(
            key: const Key('btn_cancel_delete'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('btn_confirm_delete'),
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: const Text('Masquer'),
          ),
        ],
      );
    }

    return AlertDialog(
      key: const Key('delete_doc_dialog'),
      title: const Text('Supprimer ce document ?'),
      content: Text(
        'Le fichier "${document.filename}" sera définitivement supprimé. '
        'Cette action est irréversible.',
      ),
      actions: [
        TextButton(
          key: const Key('btn_cancel_delete'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
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
          child: const Text('Supprimer'),
        ),
      ],
    );
  }
}
