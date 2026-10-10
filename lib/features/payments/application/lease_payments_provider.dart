import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/payment_repository.dart';
import '../domain/payment.dart';

final _log = Logger('LeasePaymentsNotifier');

/// Notifier qui charge et expose la liste des paiements d'un bail.
///
/// Paramétré par [leaseId] — un cache distinct par bail (invalidation chirurgicale).
/// Tri : `period_start DESC` (géré par le repository).
class LeasePaymentsNotifier extends FamilyAsyncNotifier<List<Payment>, String> {
  @override
  Future<List<Payment>> build(String arg) async {
    _log.info('fetch payments for lease=$arg');
    return ref.read(paymentRepositoryProvider).listForLease(arg);
  }

  /// Recharge la liste depuis Firestore.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(paymentRepositoryProvider).listForLease(arg),
    );
  }
}

/// Provider de la liste des paiements, paramétré par leaseId.
final leasePaymentsProvider =
    AsyncNotifierProviderFamily<LeasePaymentsNotifier, List<Payment>, String>(
      LeasePaymentsNotifier.new,
    );
