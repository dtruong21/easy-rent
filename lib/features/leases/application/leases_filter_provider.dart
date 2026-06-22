import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/lease.dart';
import '../domain/lease_filter.dart';
import '../domain/lease_list_item.dart';
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
      return switch (filter) {
        LeaseFilter.all => true,
        LeaseFilter.active =>
          lease.status == LeaseStatus.active && !_isRenewable(lease, now),
        LeaseFilter.renewable =>
          lease.status == LeaseStatus.active && _isRenewable(lease, now),
        LeaseFilter.terminated => lease.status == LeaseStatus.terminated,
      };
    }).toList();
  });
});

/// Retourne `true` si le bail est actif et sa date de fin est dans moins de 60 jours.
bool _isRenewable(Lease lease, DateTime now) {
  final end = lease.endDate;
  if (end == null) return false;
  return end.difference(now).inDays < 60;
}
