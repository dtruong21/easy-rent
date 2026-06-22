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
      if (filter == PropertyFilter.all) return items;

      return items.where((item) {
        return switch (filter) {
          PropertyFilter.all => true,
          PropertyFilter.occupied => item.activeLeaseId != null,
          PropertyFilter.vacant => item.activeLeaseId == null,
        };
      }).toList();
    });
  },
);
