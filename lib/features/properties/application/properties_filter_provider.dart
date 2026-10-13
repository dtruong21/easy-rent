import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/property_filter.dart';
import '../domain/property_list_item.dart';
import 'properties_list_provider.dart';

/// Provider du filtre actif sur la liste des biens.
///
/// État local au feature, non persisté entre sessions.
/// Initial : [PropertyFilter.all] (aucun filtre).
final propertyFilterProvider = StateProvider<PropertyFilter>(
  (ref) => PropertyFilter.all,
);

/// Provider dérivé — liste des biens filtrée selon [propertyFilterProvider].
///
/// Filtrage client-side (200 items max — OK en mémoire).
/// Re-calcule automatiquement à chaque changement de filtre ou de liste.
final filteredPropertiesProvider = Provider<AsyncValue<List<PropertyListItem>>>(
  (ref) {
    final asyncItems = ref.watch(propertiesListItemsProvider);
    final filter = ref.watch(propertyFilterProvider);

    return asyncItems.whenData((items) {
      return items
          .where((item) => propertyMatchesFilter(item, filter))
          .toList();
    });
  },
);

/// Vrai si [item] correspond à [filter]. Source unique du filtrage (liste
/// filtrée ET compteurs des puces).
bool propertyMatchesFilter(PropertyListItem item, PropertyFilter filter) =>
    switch (filter) {
      PropertyFilter.all => true,
      PropertyFilter.occupied => item.activeLeaseId != null,
      PropertyFilter.vacant => item.activeLeaseId == null,
    };

/// Nombre d'éléments par filtre (compteurs des puces).
Map<PropertyFilter, int> propertyFilterCounts(List<PropertyListItem> items) => {
  for (final f in PropertyFilter.values)
    f: items.where((i) => propertyMatchesFilter(i, f)).length,
};

/// Compteurs des puces — `null` tant que la liste n'est pas chargée.
final propertyFilterCountsProvider = Provider<Map<PropertyFilter, int>?>((ref) {
  final items = ref.watch(propertiesListItemsProvider).valueOrNull;
  return items == null ? null : propertyFilterCounts(items);
});
