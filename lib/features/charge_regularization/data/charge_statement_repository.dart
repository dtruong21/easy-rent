import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';
import '../../../core/firestore_helpers.dart';
import '../domain/charge_statement.dart';

final _log = Logger('ChargeStatementRepository');

/// Résultat de la callable `finalizeChargeRegularization` — décompte figé
/// créé côté serveur (FEAT-033, snapshot légal art. 23 loi 6/7/1989).
class ChargeStatementFinalizeResult {
  const ChargeStatementFinalizeResult({
    required this.statementId,
    required this.balanceCents,
    required this.direction,
  });

  final String statementId;
  final int balanceCents;

  /// 'dueByTenant' | 'dueToTenant' | 'balanced'
  final String direction;
}

abstract interface class ChargeStatementRepository {
  Future<List<ChargeStatement>> listForLease(String leaseId);

  Future<ChargeStatement> getById(String id);

  /// Génère un décompte de régularisation via la Callable
  /// `finalizeChargeRegularization` — snapshot immuable, jamais
  /// re-synchronisé même si les Dépenses ou paiements sources changent.
  Future<ChargeStatementFinalizeResult> finalize({
    required String leaseId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int actualExpensesCents,
    required String actualExpensesSource, // 'expenses' | 'manual'
    required List<Map<String, dynamic>> lineItems,
  });

  /// Annule un décompte via la Callable `voidChargeStatement`.
  Future<void> voidStatement(String id, String reason);

  /// Marque le décompte comme envoyé via la Callable
  /// `markChargeStatementAsSent`.
  Future<void> markAsSent({required String id, String? email});
}

class FirestoreChargeStatementRepository implements ChargeStatementRepository {
  FirestoreChargeStatementRepository(
    this._firestore,
    this._auth,
    this._functions,
  );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — charge statement ops require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('charge_statements');

  HttpsCallable _callable(String name) => _functions.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
  );

  @override
  Future<List<ChargeStatement>> listForLease(String leaseId) async {
    _log.info('listForLease(leaseId=$leaseId)');
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('leaseId', isEqualTo: leaseId)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();
    return qs.docs
        .map(
          (d) => ChargeStatement.fromJson(
            firestoreDocToSnakeJson(d.data(), docId: d.id),
          ),
        )
        .toList();
  }

  @override
  Future<ChargeStatement> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['landlordId'] != _uid) {
      throw StateError('charge statement not found: $id');
    }
    return ChargeStatement.fromJson(
      firestoreDocToSnakeJson(data, docId: snap.id),
    );
  }

  @override
  Future<ChargeStatementFinalizeResult> finalize({
    required String leaseId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int actualExpensesCents,
    required String actualExpensesSource,
    required List<Map<String, dynamic>> lineItems,
  }) async {
    _log.info('finalize(leaseId=$leaseId)');
    final res = await _callable('finalizeChargeRegularization')
        .call(<String, dynamic>{
          'leaseId': leaseId,
          'periodStart': periodStart.toUtc().toIso8601String(),
          'periodEnd': periodEnd.toUtc().toIso8601String(),
          'actualExpensesCents': actualExpensesCents,
          'actualExpensesSource': actualExpensesSource,
          'lineItems': lineItems,
        });
    final data = (res.data as Map?) ?? const {};
    final statementId = data['statementId'] as String?;
    if (statementId == null) {
      throw StateError(
        'finalizeChargeRegularization did not return a statementId',
      );
    }
    _log.info('charge statement finalized: $statementId');
    return ChargeStatementFinalizeResult(
      statementId: statementId,
      balanceCents: (data['balanceCents'] as int?) ?? 0,
      direction: (data['direction'] as String?) ?? 'balanced',
    );
  }

  @override
  Future<void> voidStatement(String id, String reason) async {
    _log.info('voidStatement(id=$id)');
    await _callable(
      'voidChargeStatement',
    ).call(<String, dynamic>{'statementId': id, 'reason': reason});
  }

  @override
  Future<void> markAsSent({required String id, String? email}) async {
    _log.info('markAsSent(id=$id)');
    await _callable(
      'markChargeStatementAsSent',
    ).call(<String, dynamic>{'statementId': id, 'email': ?email});
  }
}

final chargeStatementRepositoryProvider = Provider<ChargeStatementRepository>((
  ref,
) {
  return FirestoreChargeStatementRepository(
    ref.watch(firestoreProvider),
    FirebaseAuth.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});

/// Liste des décomptes de régularisation figés d'un bail, paramétrée par
/// `leaseId` (FEAT-033 Task 9 — historique sur la fiche bail).
///
/// `autoDispose` : pas besoin de garder ce cache vivant hors de la fiche
/// bail — même convention que les autres providers `.family` de lecture
/// ponctuelle de ce module.
final chargeStatementsForLeaseProvider = FutureProvider.family
    .autoDispose<List<ChargeStatement>, String>((ref, leaseId) {
      return ref.read(chargeStatementRepositoryProvider).listForLease(leaseId);
    });
