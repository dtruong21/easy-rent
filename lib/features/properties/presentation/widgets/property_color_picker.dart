import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/property_color.dart';
import 'property_color_l10n.dart';

/// Sélecteur de couleur d'identité — rangée de pastilles cliquables.
///
/// Affiché dans le formulaire du bien, en mode édition uniquement (la
/// couleur est attribuée automatiquement à la création — cf.
/// `PropertyColorKey.resolve`). Chaque pastille porte un `Semantics` avec le
/// nom français de la teinte pour les lecteurs d'écran.
class PropertyColorPicker extends StatelessWidget {
  const PropertyColorPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final PropertyColorKey selected;
  final ValueChanged<PropertyColorKey> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final key in PropertyColorKey.values)
          _Swatch(
            key: Key('color_swatch_${key.name}'),
            colorKey: key,
            isSelected: key == selected,
            enabled: enabled,
            onTap: () => onChanged(key),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.colorKey,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final PropertyColorKey colorKey;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  static const double _diameter = 36;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final color = colorKey.resolveColor(context);
    final label = colorKey.label(context);

    return Semantics(
      label: l10n.propertiesColorSwatchLabel(label),
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: _diameter,
          height: _diameter,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.onSurface
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? color : color.withValues(alpha: 0.4),
            ),
            child: isSelected
                ? Icon(
                    Icons.check,
                    size: 16,
                    color:
                        ThemeData.estimateBrightnessForColor(color) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
