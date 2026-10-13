import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/cards/view_mode_toggle.dart';
import '../../../../core/ui/filters/filter_chips_bar.dart';
import '../../application/leases_filter_provider.dart';
import '../../domain/lease_filter.dart';
import '../lease_filter_l10n.dart';

/// Barre de filtres + toggle de vue pour la page Leases.
///
/// Puces de filtre ([FilterChipsBar]) avec compteurs, sur toutes les
/// largeurs. Le [ViewModeToggle] reste fixe à droite (masqué sur mobile).
class LeasesFilterBar extends ConsumerWidget {
  const LeasesFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(leaseFilterProvider);
    final counts = ref.watch(leaseFilterCountsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: FilterChipsBar<LeaseFilter>(
        options: [
          for (final f in LeaseFilter.values)
            FilterChipOption(
              value: f,
              label: f.label(context),
              count: counts?[f],
            ),
        ],
        selected: current,
        onSelected: (f) => ref.read(leaseFilterProvider.notifier).state = f,
        trailing: context.isMobile
            ? null
            : const ViewModeToggle(pageKey: 'leases'),
      ),
    );
  }
}
