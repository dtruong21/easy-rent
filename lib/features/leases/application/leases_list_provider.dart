import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/lease_repository.dart';
import '../domain/lease_list_item.dart';

final _log = Logger('LeasesListNotifier');

/// Notifier qui charge et expose la liste des baux du landlord courant,
/// joints avec property + tenant pour l'affichage.
///
/// Expose une méthode [refresh] pour recharger la liste après une action
/// (création, modification, clôture, archivage).
class LeasesListNotifier extends AsyncNotifier<List<LeaseListItem>> {
  @override
  Future<List<LeaseListItem>> build() async {
    return _fetch();
  }

  Future<List<LeaseListItem>> _fetch() async {
    _log.info('fetch leases list');
    return ref.read(leaseRepositoryProvider).listForDisplay();
  }

  /// Recharge la liste depuis Supabase.
  ///
  /// À appeler après une création, modification, clôture ou archivage réussis.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }
}

/// Provider de la liste des baux.
final leasesListProvider =
    AsyncNotifierProvider<LeasesListNotifier, List<LeaseListItem>>(
      LeasesListNotifier.new,
    );
