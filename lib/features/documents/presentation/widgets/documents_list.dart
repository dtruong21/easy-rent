import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../domain/document.dart';
import 'document_list_tile.dart';

/// Liste des documents d'un bail.
///
/// Affiche soit la liste des [documents], soit un empty state si vide.
class DocumentsList extends StatelessWidget {
  const DocumentsList({
    super.key,
    required this.documents,
    required this.leaseId,
  });

  final List<Document> documents;
  final String leaseId;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return _EmptyDocumentsState();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: documents
          .map((doc) => DocumentListTile(document: doc, leaseId: leaseId))
          .toList(),
    );
  }
}

/// Empty state cohérent PR #18 (wording positif, icône primary).
class _EmptyDocumentsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.documentsEmptyTitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.documentsUploadPromptText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
