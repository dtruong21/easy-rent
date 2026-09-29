import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/lease_filter.dart';
import '../domain/lease_list_item.dart';
import '../domain/lease_renewal.dart';
import '../domain/lease_status.dart';
import 'leases_list_provider.dart';

/// Provider du filtre actif sur la liste des baux.
///
/// État local au feature, non persisté entre sessions.
/// Initial : [LeaseFilter.all] (aucun filtre).
final leaseFilterProvider = StateProvider<LeaseFilter>(
  (ref) => LeaseFilter.all,
);

/// Provider dérivé — liste des baux filtrée selon [leaseFilterProvider].
///
/// Filtrage client-side (200 items max — OK en mémoire).
/// Re-calcule automatiquement à chaque changement de filtre ou de liste.
final filteredLeasesProvider = Provider<AsyncValue<List<LeaseListItem>>>((ref) {
  final asyncLeases = ref.watch(leasesListProvider);
  final filter = ref.watch(leaseFilterProvider);

  return asyncLeases.whenData((leases) {
    final now = DateTime.now();
    return leases
        .where((item) => leaseMatchesFilter(item, filter, now))
        .toList();
  });
});

/// Vrai si [item] correspond à [filter]. Priorité (FEAT-028) : late >
/// renewable > active — un bail n'apparaît que dans un seul onglet.
bool leaseMatchesFilter(LeaseListItem item, LeaseFilter filter, DateTime now) {
  final lease = item.lease;
  return switch (filter) {
    LeaseFilter.all => true,
    LeaseFilter.active =>
      lease.status == LeaseStatus.active &&
          !item.isLate &&
          !isLeaseRenewable(lease, now),
    LeaseFilter.renewable =>
      lease.status == LeaseStatus.active &&
          !item.isLate &&
          isLeaseRenewable(lease, now),
    LeaseFilter.late => lease.status == LeaseStatus.active && item.isLate,
    LeaseFilter.terminated => lease.status == LeaseStatus.terminated,
  };
}

/// Nombre d'éléments par filtre (compteurs des puces).
Map<LeaseFilter, int> leaseFilterCounts(
  List<LeaseListItem> items,
  DateTime now,
) => {
  for (final f in LeaseFilter.values)
    f: items.where((i) => leaseMatchesFilter(i, f, now)).length,
};

/// Compteurs des puces — `null` tant que la liste n'est pas chargée.
final leaseFilterCountsProvider = Provider<Map<LeaseFilter, int>?>((ref) {
  final items = ref.watch(leasesListProvider).valueOrNull;
  return items == null ? null : leaseFilterCounts(items, DateTime.now());
});
