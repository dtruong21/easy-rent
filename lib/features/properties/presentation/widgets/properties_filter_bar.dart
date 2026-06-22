import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/cards/view_mode_toggle.dart';
import '../../application/properties_filter_provider.dart';
import '../../domain/property_filter.dart';

/// Barre de filtres + toggle de vue pour la page Properties.
///
/// Sur mobile (<600px) : [DropdownButton] simple + ViewModeToggle masqué.
/// Sur tablette/desktop (>=600px) : [SegmentedButton] 3 segments + [ViewModeToggle].
class PropertiesFilterBar extends ConsumerWidget {
  const PropertiesFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(propertyFilterProvider);
    final isMobile = context.isMobile;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: isMobile
                ? _MobileFilterDropdown(
                    currentFilter: currentFilter,
                    onChanged: (f) {
                      if (f != null) {
                        ref.read(propertyFilterProvider.notifier).state = f;
                      }
                    },
                  )
                : _DesktopFilterSegments(
                    currentFilter: currentFilter,
                    onChanged: (f) =>
                        ref.read(propertyFilterProvider.notifier).state = f,
                  ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 12),
            const ViewModeToggle(pageKey: 'properties'),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented button (tablette / desktop)
// ---------------------------------------------------------------------------

class _DesktopFilterSegments extends StatelessWidget {
  const _DesktopFilterSegments({
    required this.currentFilter,
    required this.onChanged,
  });

  final PropertyFilter currentFilter;
  final void Function(PropertyFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PropertyFilter>(
      segments: PropertyFilter.values
          .map(
            (f) =>
                ButtonSegment<PropertyFilter>(value: f, label: Text(f.labelFr)),
          )
          .toList(),
      selected: {currentFilter},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
      showSelectedIcon: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Dropdown (mobile)
// ---------------------------------------------------------------------------

class _MobileFilterDropdown extends StatelessWidget {
  const _MobileFilterDropdown({
    required this.currentFilter,
    required this.onChanged,
  });

  final PropertyFilter currentFilter;
  final void Function(PropertyFilter?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButton<PropertyFilter>(
      value: currentFilter,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      style: theme.textTheme.bodyMedium,
      items: PropertyFilter.values
          .map(
            (f) => DropdownMenuItem<PropertyFilter>(
              value: f,
              child: Text(f.labelFr),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
