import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leases/application/leases_list_provider.dart';
import '../../leases/domain/lease_list_item.dart';
import '../../leases/domain/lease_renewal.dart';
import '../../leases/domain/lease_status.dart';

/// Items actionnables dérivés de la liste des baux, pour le panneau
/// « À traiter / À venir » du dashboard. Aucune requête propre : dérive
/// [leasesListProvider] (même source que l'écran Baux).
class DashboardActionItems {
  const DashboardActionItems({required this.late, required this.ending});

  /// Baux actifs en retard de paiement (FEAT-028).
  final List<LeaseListItem> late;

  /// Baux actifs, non en retard, dont la date de fin est < 60 j.
  final List<LeaseListItem> ending;

  bool get isEmpty => late.isEmpty && ending.isEmpty;
}

/// Priorité FEAT-028 : late > renewable. Un bail en retard n'est jamais dans
/// [DashboardActionItems.ending].
final dashboardActionItemsProvider = Provider<AsyncValue<DashboardActionItems>>(
  (ref) {
    final asyncLeases = ref.watch(leasesListProvider);
    final now = DateTime.now();
    return asyncLeases.whenData((leases) {
      final late = leases
          .where((i) => i.lease.status == LeaseStatus.active && i.isLate)
          .toList();
      final ending = leases
          .where(
            (i) =>
                i.lease.status == LeaseStatus.active &&
                !i.isLate &&
                isLeaseRenewable(i.lease, now),
          )
          .toList();
      return DashboardActionItems(late: late, ending: ending);
    });
  },
);
