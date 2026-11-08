import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/breakpoints.dart';
import '../../../../core/ui/cards/view_mode_toggle.dart';
import '../../../../core/ui/filters/filter_chips_bar.dart';
import '../../application/tenants_filter_provider.dart';
import '../../domain/tenant_filter.dart';
import '../tenant_filter_l10n.dart';

/// Barre de filtres + toggle de vue pour la page Tenants.
///
/// Puces de filtre ([FilterChipsBar]) avec compteurs, sur toutes les
/// largeurs. Le [ViewModeToggle] reste fixe à droite (masqué sur mobile).
class TenantsFilterBar extends ConsumerWidget {
  const TenantsFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(tenantFilterProvider);
    final counts = ref.watch(tenantFilterCountsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: FilterChipsBar<TenantFilter>(
        options: [
          for (final f in TenantFilter.values)
            FilterChipOption(
              value: f,
              label: f.label(context),
              count: counts?[f],
            ),
        ],
        selected: current,
        onSelected: (f) => ref.read(tenantFilterProvider.notifier).state = f,
        trailing: context.isMobile
            ? null
            : const ViewModeToggle(pageKey: 'tenants'),
      ),
    );
  }
}
