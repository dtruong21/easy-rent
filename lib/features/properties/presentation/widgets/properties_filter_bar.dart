import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/cards/view_mode_toggle.dart';
import '../../../../core/ui/filters/filter_chips_bar.dart';
import '../../application/properties_filter_provider.dart';
import '../../domain/property_filter.dart';
import 'property_filter_l10n.dart';

/// Barre de filtres + toggle de vue pour la page Properties.
///
/// Puces de filtre ([FilterChipsBar]) avec compteurs, sur toutes les
/// largeurs. Le [ViewModeToggle] reste fixe à droite (masqué sur mobile).
class PropertiesFilterBar extends ConsumerWidget {
  const PropertiesFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(propertyFilterProvider);
    final counts = ref.watch(propertyFilterCountsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: FilterChipsBar<PropertyFilter>(
        options: [
          for (final f in PropertyFilter.values)
            FilterChipOption(
              value: f,
              label: f.label(context),
              count: counts?[f],
            ),
        ],
        selected: current,
        onSelected: (f) => ref.read(propertyFilterProvider.notifier).state = f,
        trailing: context.isMobile
            ? null
            : const ViewModeToggle(pageKey: 'properties'),
      ),
    );
  }
}
