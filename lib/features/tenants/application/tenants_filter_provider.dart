import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/tenant_filter.dart';
import '../domain/tenant_list_item.dart';
import 'tenants_list_provider.dart';

/// Provider du filtre actif sur la liste des locataires.
///
/// État local au feature, non persisté entre sessions.
/// Initial : [TenantFilter.all] (aucun filtre).
final tenantFilterProvider = StateProvider<TenantFilter>(
  (ref) => TenantFilter.all,
);

/// Provider dérivé — liste des locataires filtrée selon [tenantFilterProvider].
///
/// Filtrage client-side (200 items max — OK en mémoire).
/// Re-calcule automatiquement à chaque changement de filtre ou de liste.
final filteredTenantsProvider = Provider<AsyncValue<List<TenantListItem>>>((
  ref,
) {
  final asyncItems = ref.watch(tenantsListItemsProvider);
  final filter = ref.watch(tenantFilterProvider);

  return asyncItems.whenData((items) {
    if (filter == TenantFilter.all) return items;

    return items.where((item) {
      return switch (filter) {
        TenantFilter.all => true,
        TenantFilter.withActiveLease => item.activeLeaseId != null,
        TenantFilter.withoutActiveLease => item.activeLeaseId == null,
      };
    }).toList();
  });
});
