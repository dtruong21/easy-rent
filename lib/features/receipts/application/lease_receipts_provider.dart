import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/receipts_repository.dart';
import '../domain/receipt.dart';

final _log = Logger('LeaseReceiptsNotifier');

/// Notifier qui charge et expose la liste des quittances d'un bail.
///
/// Paramétré par [leaseId] — un cache distinct par bail (invalidation chirurgicale).
/// Tri : `period_start DESC` (géré par le repository).
/// Inclut les quittances annulées — filtrables côté UI via [isVoided].
class LeaseReceiptsNotifier extends FamilyAsyncNotifier<List<Receipt>, String> {
  @override
  Future<List<Receipt>> build(String arg) async {
    _log.info('fetch receipts for lease=$arg');
    return ref.read(receiptsRepositoryProvider).listForLease(arg);
  }

  /// Recharge la liste depuis Firestore.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(receiptsRepositoryProvider).listForLease(arg),
    );
  }
}

/// Provider de la liste des quittances, paramétré par leaseId.
final leaseReceiptsProvider =
    AsyncNotifierProviderFamily<LeaseReceiptsNotifier, List<Receipt>, String>(
      LeaseReceiptsNotifier.new,
    );
