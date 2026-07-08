import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/cards/view_mode_toggle.dart';
import '../../application/leases_filter_provider.dart';
import '../../domain/lease_filter.dart';
import '../lease_filter_l10n.dart';

/// Barre de filtres + toggle de vue pour la page Leases.
///
/// Sur mobile (<600px) : [DropdownButton] simple + ViewModeToggle masqué.
/// Sur tablette/desktop (>=600px) : [SegmentedButton] 4 segments + [ViewModeToggle].
class LeasesFilterBar extends ConsumerWidget {
  const LeasesFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(leaseFilterProvider);
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
                        ref.read(leaseFilterProvider.notifier).state = f;
                      }
                    },
                  )
                : _DesktopFilterSegments(
                    currentFilter: currentFilter,
                    onChanged: (f) =>
                        ref.read(leaseFilterProvider.notifier).state = f,
                  ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 12),
            const ViewModeToggle(pageKey: 'leases'),
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

  final LeaseFilter currentFilter;
  final void Function(LeaseFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LeaseFilter>(
      segments: LeaseFilter.values
          .map(
            (f) => ButtonSegment<LeaseFilter>(
              value: f,
              label: Text(f.label(context)),
            ),
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

  final LeaseFilter currentFilter;
  final void Function(LeaseFilter?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButton<LeaseFilter>(
      value: currentFilter,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      style: theme.textTheme.bodyMedium,
      items: LeaseFilter.values
          .map(
            (f) => DropdownMenuItem<LeaseFilter>(
              value: f,
              child: Text(f.label(context)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
