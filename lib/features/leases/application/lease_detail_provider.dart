import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/lease_repository.dart';
import '../domain/lease.dart';

final _log = Logger('LeaseDetailNotifier');

/// Notifier qui charge un bail par son [id].
///
/// Lance [LeaseNotFoundException] si les Firestore Rules ne renvoient aucun document
/// (bail archivé, non possédé, ou id inconnu — pas de fuite d'information).
class LeaseDetailNotifier extends FamilyAsyncNotifier<Lease, String> {
  @override
  Future<Lease> build(String arg) async {
    _log.info('fetch lease detail id=$arg');
    return ref.read(leaseRepositoryProvider).getById(arg);
  }

  /// Recharge la fiche depuis Firestore.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(leaseRepositoryProvider).getById(arg),
    );
  }
}

/// Provider de la fiche d'un bail, paramétré par l'id.
final leaseDetailProvider =
    AsyncNotifierProviderFamily<LeaseDetailNotifier, Lease, String>(
      LeaseDetailNotifier.new,
    );
