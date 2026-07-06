import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/cards/view_mode_toggle.dart';
import '../../application/tenants_filter_provider.dart';
import '../../domain/tenant_filter.dart';
import '../tenant_filter_l10n.dart';

/// Barre de filtres + toggle de vue pour la page Tenants.
///
/// Sur mobile (<600px) : [DropdownButton] simple + ViewModeToggle masqué.
/// Sur tablette/desktop (>=600px) : [SegmentedButton] 3 segments + [ViewModeToggle].
class TenantsFilterBar extends ConsumerWidget {
  const TenantsFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFilter = ref.watch(tenantFilterProvider);
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
                        ref.read(tenantFilterProvider.notifier).state = f;
                      }
                    },
                  )
                : _DesktopFilterSegments(
                    currentFilter: currentFilter,
                    onChanged: (f) =>
                        ref.read(tenantFilterProvider.notifier).state = f,
                  ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 12),
            const ViewModeToggle(pageKey: 'tenants'),
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

  final TenantFilter currentFilter;
  final void Function(TenantFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TenantFilter>(
      segments: TenantFilter.values
          .map(
            (f) => ButtonSegment<TenantFilter>(
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

  final TenantFilter currentFilter;
  final void Function(TenantFilter?) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownButton<TenantFilter>(
      value: currentFilter,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      style: theme.textTheme.bodyMedium,
      items: TenantFilter.values
          .map(
            (f) => DropdownMenuItem<TenantFilter>(
              value: f,
              child: Text(f.label(context)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
