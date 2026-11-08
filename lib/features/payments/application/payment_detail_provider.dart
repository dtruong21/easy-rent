import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/payment_repository.dart';
import '../domain/payment.dart';

final _log = Logger('PaymentDetailProvider');

/// Provider qui charge un paiement par son [id].
///
/// Lance [PaymentNotFoundException] si les Firestore Rules ne renvoient aucun document
/// (paiement archivé, non possédé, ou id inconnu).
final paymentDetailProvider = FutureProvider.family<Payment, String>((
  ref,
  id,
) async {
  _log.info('fetch payment detail id=$id');
  return ref.read(paymentRepositoryProvider).getById(id);
});
