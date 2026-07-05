import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/firestore_helpers.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';
import '../domain/expense_nature.dart';

final _log = Logger('ExpensesRepository');

const int _kMaxExpensesPerList = 500;

/// Dépenses = entité first-class « l'argent qui sort » (FEAT-041).
///
/// Collection **CF-EXCLUSIVE** — toute écriture passe par les Callables
/// `createExpense` (validation cross-entity property+lease, dérivation
/// serveur de [ExpenseCategory]) / `updateExpense` / `softDeleteEntity`.
/// Lecture directe Firestore (streams filtrés `landlordId==uid &&
/// deletedAt==null`), voir `docs/plans/FEAT-041-depenses.md` § b)/h).
///
/// [documentId] (FEAT-041b) : justificatif optionnel, uploadé au préalable
/// via `DocumentsRepository.upload` (catégorie `expense_receipt`) — voir
/// § g) du plan. **Recommandé, non bloquant** : une dépense peut être créée
/// sans justificatif (décision produit #8).
abstract interface class ExpensesRepository {
  /// Liste (one-shot) les dépenses actives d'un bien, triées par
  /// `expenseDate DESC`.
  Future<List<Expense>> listForProperty(String propertyId);

  /// Stream temps réel des dépenses actives d'un bien, triées par
  /// `expenseDate DESC`.
  Stream<List<Expense>> watchForProperty(String propertyId);

  Future<Expense> getById(String id);

  /// Crée une nouvelle dépense via la Callable `createExpense`.
  ///
  /// [documentId] : justificatif optionnel (déjà uploadé — voir
  /// `ExpenseReceiptUploadController`), transmis tel quel à la Callable.
  Future<Expense> create({
    required String propertyId,
    String? leaseId,
    required int amountCents,
    required DateTime expenseDate,
    required ExpenseNature nature,
    ExpenseCategory? category,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? periodYear,
    String? documentId,
    String? notes,
  });

  /// Met à jour les champs mutables via la Callable `updateExpense`.
  /// `propertyId`/`leaseId`/`landlordId`/`createdAt` sont IMMUABLES.
  Future<Expense> update(Expense expense);

  /// Archive (soft-delete) via la Callable `softDeleteEntity`.
  Future<void> archive(String id);
}

class FirestoreExpensesRepository implements ExpensesRepository {
  FirestoreExpensesRepository(this._firestore, this._auth, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — expense operations require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('expenses');

  HttpsCallable _callable(String name) => _functions.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
  );

  Query<Map<String, dynamic>> _forPropertyQuery(String propertyId) => _col
      .where('landlordId', isEqualTo: _uid)
      .where('propertyId', isEqualTo: propertyId)
      .where('deletedAt', isNull: true)
      .orderBy('expenseDate', descending: true)
      .limit(_kMaxExpensesPerList);

  @override
  Future<List<Expense>> listForProperty(String propertyId) async {
    _log.info('listForProperty(propertyId=$propertyId)');
    final qs = await _forPropertyQuery(propertyId).get();
    return qs.docs
        .map(
          (d) =>
              Expense.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)),
        )
        .toList();
  }

  @override
  Stream<List<Expense>> watchForProperty(String propertyId) {
    _log.info('watchForProperty(propertyId=$propertyId)');
    return _forPropertyQuery(propertyId).snapshots().map(
      (qs) => qs.docs
          .map(
            (d) => Expense.fromJson(
              firestoreDocToSnakeJson(d.data(), docId: d.id),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<Expense> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['deletedAt'] != null) {
      throw ExpenseNotFoundException(id);
    }
    if (data['landlordId'] != _uid) {
      throw ExpenseNotFoundException(id);
    }
    return Expense.fromJson(firestoreDocToSnakeJson(data, docId: snap.id));
  }

  @override
  Future<Expense> create({
    required String propertyId,
    String? leaseId,
    required int amountCents,
    required DateTime expenseDate,
    required ExpenseNature nature,
    ExpenseCategory? category,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? periodYear,
    String? documentId,
    String? notes,
  }) async {
    _log.info('create(propertyId=$propertyId, nature=${nature.sqlValue})');
    final res = await _callable('createExpense').call(<String, dynamic>{
      'propertyId': propertyId,
      'leaseId': leaseId,
      'amountCents': amountCents,
      'expenseDate': expenseDate.toUtc().toIso8601String(),
      'nature': nature.sqlValue,
      'category': category?.sqlValue,
      'periodStart': periodStart?.toUtc().toIso8601String(),
      'periodEnd': periodEnd?.toUtc().toIso8601String(),
      'periodYear': periodYear,
      'documentId': documentId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    final expenseId = (res.data as Map?)?['expenseId'] as String?;
    if (expenseId == null) {
      throw StateError('createExpense did not return an expenseId');
    }
    return getById(expenseId);
  }

  @override
  Future<Expense> update(Expense expense) async {
    _log.info('update(id=${expense.id})');
    final patch = <String, dynamic>{
      'amountCents': expense.amountCents,
      'expenseDate': expense.expenseDate.toUtc().toIso8601String(),
      'nature': expense.nature.sqlValue,
      'category': expense.category.sqlValue,
      'periodYear': expense.periodYear,
      'periodStart': expense.periodStart?.toUtc().toIso8601String(),
      'periodEnd': expense.periodEnd?.toUtc().toIso8601String(),
      'documentId': expense.documentId,
      'notes': expense.notes,
    };
    await _callable(
      'updateExpense',
    ).call(<String, dynamic>{'id': expense.id, 'patch': patch});
    return getById(expense.id);
  }

  @override
  Future<void> archive(String id) async {
    _log.info('archive($id)');
    await _callable(
      'softDeleteEntity',
    ).call(<String, dynamic>{'collection': 'expenses', 'id': id});
  }
}

class ExpenseNotFoundException implements Exception {
  const ExpenseNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'ExpenseNotFoundException: dépense $id introuvable';
}

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return FirestoreExpensesRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});
