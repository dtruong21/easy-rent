import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/firestore_helpers.dart';
import '../domain/payment.dart';
import '../domain/payment_method.dart';

final _log = Logger('PaymentRepository');

abstract interface class PaymentRepository {
  /// Liste tous les paiements d'un bail, triés par periodStart DESC.
  Future<List<Payment>> listForLease(String leaseId);

  Future<Payment> getById(String id);

  /// Crée un nouveau paiement via la Callable `createPayment` (validation
  /// cross-entity lease.landlordId == uid + denorm snapshot
  /// propertyName/tenantLastName).
  Future<Payment> create({
    required String leaseId,
    required String landlordId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime paidAt,
    required int rentAmountCents,
    required int chargesAmountCents,
    required PaymentMethod paymentMethod,
    String? notes,
    String? reference,
  });

  /// Met à jour les champs mutables via la Callable `updatePayment`.
  /// Note : périodes et montants sont IMMUABLES post-création (loi 1989).
  Future<Payment> update(Payment payment);

  /// Archive (soft-delete) via la Callable `softDeleteEntity`.
  /// Le trigger `recomputeReceiptStale` mettra `isStale=true` sur les
  /// receipts qui référencent ce payment.
  Future<void> archive(String id);
}

class FirestorePaymentRepository implements PaymentRepository {
  FirestorePaymentRepository(this._firestore, this._auth, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — payment operations require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('payments');

  HttpsCallable _callable(String name) => _functions.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
  );

  @override
  Future<List<Payment>> listForLease(String leaseId) async {
    _log.info('listForLease(leaseId=$leaseId)');
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('leaseId', isEqualTo: leaseId)
        .where('deletedAt', isEqualTo: null)
        .orderBy('periodStart', descending: true)
        .limit(200)
        .get();
    return qs.docs
        .map(
          (d) =>
              Payment.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)),
        )
        .toList();
  }

  @override
  Future<Payment> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['deletedAt'] != null) {
      throw PaymentNotFoundException(id);
    }
    if (data['landlordId'] != _uid) {
      throw PaymentNotFoundException(id);
    }
    return Payment.fromJson(firestoreDocToSnakeJson(data, docId: snap.id));
  }

  @override
  Future<Payment> create({
    required String leaseId,
    required String landlordId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime paidAt,
    required int rentAmountCents,
    required int chargesAmountCents,
    required PaymentMethod paymentMethod,
    String? notes,
    String? reference,
  }) async {
    _log.info('create(leaseId=$leaseId)');
    final res = await _callable('createPayment').call(<String, dynamic>{
      'leaseId': leaseId,
      'periodStart': periodStart.toUtc().toIso8601String(),
      'periodEnd': periodEnd.toUtc().toIso8601String(),
      'paidAt': paidAt.toUtc().toIso8601String(),
      'rentAmountCents': rentAmountCents,
      'chargesAmountCents': chargesAmountCents,
      'paymentMethod': paymentMethod.sqlValue,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    });
    final paymentId = (res.data as Map?)?['paymentId'] as String?;
    if (paymentId == null) {
      throw StateError('createPayment did not return a paymentId');
    }
    return getById(paymentId);
  }

  @override
  Future<Payment> update(Payment payment) async {
    _log.info('update(id=${payment.id})');
    final patch = <String, dynamic>{
      'paidAt': payment.paidAt.toUtc().toIso8601String(),
      'paymentMethod': payment.paymentMethod.sqlValue,
      'notes': payment.notes,
      'reference': payment.reference,
    };
    await _callable(
      'updatePayment',
    ).call(<String, dynamic>{'id': payment.id, 'patch': patch});
    return getById(payment.id);
  }

  @override
  Future<void> archive(String id) async {
    _log.info('archive($id)');
    // softDeleteEntity ne supporte PAS les payments (intentionnel — payments
    // immutables loi 1989 sauf via flow dédié). On utilise une transaction
    // Firestore directe : Rules bloquent en write (allow update: if false)
    // donc on doit appeler une Callable. Cependant, dans la spec actuelle, on
    // n'a pas de "softDeletePayment" séparée — on étend softDeleteEntity pour
    // accepter 'payments' OU on crée une Callable spécifique. Pour l'instant
    // on n'archive PAS les payments depuis l'app : c'est une opération admin.
    throw UnsupportedError(
      'Archiving payments not supported in MVP — payments are immutable '
      '(loi 6 juillet 1989). For audit corrections, use void receipt instead.',
    );
  }
}

class PaymentNotFoundException implements Exception {
  const PaymentNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'PaymentNotFoundException: paiement $id introuvable';
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return FirestorePaymentRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});
