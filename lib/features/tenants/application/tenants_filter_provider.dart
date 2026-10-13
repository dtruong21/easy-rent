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
    return items.where((item) => tenantMatchesFilter(item, filter)).toList();
  });
});

/// Vrai si [item] correspond à [filter]. Source unique du filtrage (liste
/// filtrée ET compteurs des puces).
bool tenantMatchesFilter(TenantListItem item, TenantFilter filter) =>
    switch (filter) {
      TenantFilter.all => true,
      TenantFilter.withActiveLease => item.activeLeaseId != null,
      TenantFilter.withoutActiveLease => item.activeLeaseId == null,
    };

/// Nombre d'éléments par filtre (compteurs des puces).
Map<TenantFilter, int> tenantFilterCounts(List<TenantListItem> items) => {
  for (final f in TenantFilter.values)
    f: items.where((i) => tenantMatchesFilter(i, f)).length,
};

/// Compteurs des puces — `null` tant que la liste n'est pas chargée.
final tenantFilterCountsProvider = Provider<Map<TenantFilter, int>?>((ref) {
  final items = ref.watch(tenantsListItemsProvider).valueOrNull;
  return items == null ? null : tenantFilterCounts(items);
});
