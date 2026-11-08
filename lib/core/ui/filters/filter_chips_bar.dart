import 'package:flutter/material.dart';

/// Option d'une [FilterChipsBar].
class FilterChipOption<T> {
  const FilterChipOption({
    required this.value,
    required this.label,
    this.count,
  });

  final T value;
  final String label;

  /// Nombre d'éléments correspondant au filtre. `null` → pas de compteur
  /// (liste encore en chargement).
  final int? count;
}

/// Rangée de puces de filtre avec compteurs (spec 2026-09-29, D4).
///
/// Défile horizontalement quand les puces dépassent la largeur. [trailing]
/// (ex. `ViewModeToggle` sur desktop, sélecteur d'année des quittances)
/// reste fixe à droite.
class FilterChipsBar<T> extends StatelessWidget {
  const FilterChipsBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.trailing,
  });

  final List<FilterChipOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in options)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _chip(option, colors),
                  ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }

  Widget _chip(FilterChipOption<T> option, ColorScheme colors) {
    final isSelected = option.value == selected;
    final fg = isSelected ? colors.onPrimary : colors.onSurface;
    return ChoiceChip(
      key: Key('filter_chip_${option.value}'),
      selected: isSelected,
      showCheckmark: false,
      selectedColor: colors.primary,
      onSelected: (_) => onSelected(option.value),
      label: Text.rich(
        TextSpan(
          text: option.label,
          style: TextStyle(color: fg),
          children: [
            if (option.count != null)
              TextSpan(
                text: '  ${option.count}',
                style: TextStyle(color: fg.withValues(alpha: 0.7)),
              ),
          ],
        ),
      ),
    );
  }
}
