import 'package:flutter/material.dart';

import '../../domain/document_category.dart';

/// Dialog de sélection de catégorie pour un document.
///
/// Affiche les 5 catégories disponibles dans un [DropdownButton].
/// Retourne la catégorie sélectionnée via `Navigator.pop<DocumentCategory>`
/// lors de la validation — à consommer avec `showDialog<DocumentCategory>`.
///
/// [onSelect] est optionnel et conservé pour les call sites qui ne passent
/// pas par `showDialog` (rétrocompatibilité).
class EditCategoryDialog extends StatefulWidget {
  const EditCategoryDialog({
    super.key,
    required this.currentCategory,
    this.onSelect,
  });

  final DocumentCategory currentCategory;
  final void Function(DocumentCategory)? onSelect;

  @override
  State<EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<EditCategoryDialog> {
  late DocumentCategory _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentCategory;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('edit_category_dialog'),
      title: const Text('Modifier la catégorie'),
      content: DropdownButton<DocumentCategory>(
        key: const Key('category_dropdown'),
        value: _selected,
        isExpanded: true,
        items: DocumentCategory.values
            .map(
              (cat) => DropdownMenuItem(
                value: cat,
                child: Row(
                  children: [
                    Icon(cat.icon, size: 18),
                    const SizedBox(width: 8),
                    Text(cat.label),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (cat) {
          if (cat != null) setState(() => _selected = cat);
        },
      ),
      actions: [
        TextButton(
          key: const Key('btn_cancel_category'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('btn_confirm_category'),
          onPressed: () {
            Navigator.of(context).pop(_selected);
            widget.onSelect?.call(_selected);
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
