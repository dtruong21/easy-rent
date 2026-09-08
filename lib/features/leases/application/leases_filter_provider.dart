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
    if (filter == LeaseFilter.all) return leases;

    final now = DateTime.now();
    return leases.where((item) {
      final lease = item.lease;
      // Priorité d'affichage (FEAT-028) : late > renewable > active. Un bail
      // en retard ne doit apparaître ni dans `active` ni dans `renewable` —
      // sinon il serait démultiplié entre plusieurs onglets de filtre.
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
    }).toList();
  });
});
