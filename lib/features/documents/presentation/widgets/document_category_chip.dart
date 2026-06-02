import 'package:flutter/material.dart';

import '../../domain/document_category.dart';

/// Chip affichant la catégorie d'un document avec son icône et son libellé FR.
class DocumentCategoryChip extends StatelessWidget {
  const DocumentCategoryChip({super.key, required this.category});

  final DocumentCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(
        category.icon,
        size: 14,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      label: Text(
        category.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}
