import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/firestore_helpers.dart';
import '../domain/investment_scenario.dart';

final _log = Logger('InvestmentScenarioRepository');

abstract interface class InvestmentScenarioRepository {
  Future<List<InvestmentScenario>> list();

  Future<InvestmentScenario> getById(String id);

  Future<InvestmentScenario> create({
    required String name,
    required int purchasePriceCents,
    int notaryFeesCents,
    int worksInitialCents,
    bool isNewProperty,
    int downPaymentCents,
    int loanPrincipalCents,
    int loanRateBps,
    int loanDurationMonths,
    required int monthlyRentHcCents,
    int propertyTaxAnnualCents,
    int insurancePnoAnnualCents,
    int condoFeesNonRecoverableCents,
    String? notes,
  });

  Future<InvestmentScenario> update(InvestmentScenario scenario);

  Future<void> softDelete(String id);
}

class FirestoreInvestmentScenarioRepository
    implements InvestmentScenarioRepository {
  FirestoreInvestmentScenarioRepository(
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
      throw StateError('Not authenticated — scenario operations require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('investment_scenarios');

  @override
  Future<List<InvestmentScenario>> list() async {
    _log.info('list()');
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('deletedAt', isEqualTo: null)
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .get();
    return qs.docs
        .map(
          (d) => InvestmentScenario.fromJson(
            firestoreDocToSnakeJson(d.data(), docId: d.id),
          ),
        )
        .toList();
  }

  @override
  Future<InvestmentScenario> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['deletedAt'] != null) {
      throw InvestmentScenarioNotFoundException(id);
    }
    if (data['landlordId'] != _uid) {
      throw InvestmentScenarioNotFoundException(id);
    }
    return InvestmentScenario.fromJson(
      firestoreDocToSnakeJson(data, docId: snap.id),
    );
  }

  @override
  Future<InvestmentScenario> create({
    required String name,
    required int purchasePriceCents,
    int notaryFeesCents = 0,
    int worksInitialCents = 0,
    bool isNewProperty = false,
    int downPaymentCents = 0,
    int loanPrincipalCents = 0,
    int loanRateBps = 0,
    int loanDurationMonths = 240,
    required int monthlyRentHcCents,
    int propertyTaxAnnualCents = 0,
    int insurancePnoAnnualCents = 0,
    int condoFeesNonRecoverableCents = 0,
    String? notes,
  }) async {
    _log.info('create(name=$name)');
    final uid = _uid;
    final docRef = _col.doc();
    final now = FieldValue.serverTimestamp();

    // scenario_json est un map JSON arbitraire — on encode tous les
    // paramètres financiers dedans pour rester aligné avec le schéma
    // Firestore (cf. docs/plans/FEAT-019-firestore-data-model.md §1.8).
    final scenarioJson = <String, dynamic>{
      'purchasePriceCents': purchasePriceCents,
      'notaryFeesCents': notaryFeesCents,
      'worksInitialCents': worksInitialCents,
      'isNewProperty': isNewProperty,
      'downPaymentCents': downPaymentCents,
      'loanPrincipalCents': loanPrincipalCents,
      'loanRateBps': loanRateBps,
      'loanDurationMonths': loanDurationMonths,
      'monthlyRentHcCents': monthlyRentHcCents,
      'propertyTaxAnnualCents': propertyTaxAnnualCents,
      'insurancePnoAnnualCents': insurancePnoAnnualCents,
      'condoFeesNonRecoverableCents': condoFeesNonRecoverableCents,
    };

    final payload = <String, dynamic>{
      'id': docRef.id,
      'landlordId': uid,
      'name': name.trim(),
      'scenarioJson': scenarioJson,
      'schemaVersion': 1,
      'notes': notes?.trim(),
      // Champs scénario expandés en root (compat freezed Model qui les
      // attend en top-level snake_case).
      'purchasePriceCents': purchasePriceCents,
      'notaryFeesCents': notaryFeesCents,
      'worksInitialCents': worksInitialCents,
      'isNewProperty': isNewProperty,
      'downPaymentCents': downPaymentCents,
      'loanPrincipalCents': loanPrincipalCents,
      'loanRateBps': loanRateBps,
      'loanDurationMonths': loanDurationMonths,
      'monthlyRentHcCents': monthlyRentHcCents,
      'propertyTaxAnnualCents': propertyTaxAnnualCents,
      'insurancePnoAnnualCents': insurancePnoAnnualCents,
      'condoFeesNonRecoverableCents': condoFeesNonRecoverableCents,
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    };
    await docRef.set(payload);
    final saved = await docRef.get();
    return InvestmentScenario.fromJson(
      firestoreDocToSnakeJson(saved.data()!, docId: saved.id),
    );
  }

  @override
  Future<InvestmentScenario> update(InvestmentScenario scenario) async {
    _log.info('update(id=${scenario.id})');
    final payload = <String, dynamic>{
      'name': scenario.name.trim(),
      'notes': scenario.notes,
      'purchasePriceCents': scenario.purchasePriceCents,
      'notaryFeesCents': scenario.notaryFeesCents,
      'worksInitialCents': scenario.worksInitialCents,
      'isNewProperty': scenario.isNewProperty,
      'downPaymentCents': scenario.downPaymentCents,
      'loanPrincipalCents': scenario.loanPrincipalCents,
      'loanRateBps': scenario.loanRateBps,
      'loanDurationMonths': scenario.loanDurationMonths,
      'monthlyRentHcCents': scenario.monthlyRentHcCents,
      'propertyTaxAnnualCents': scenario.propertyTaxAnnualCents,
      'insurancePnoAnnualCents': scenario.insurancePnoAnnualCents,
      'condoFeesNonRecoverableCents': scenario.condoFeesNonRecoverableCents,
      'scenarioJson': <String, dynamic>{
        'purchasePriceCents': scenario.purchasePriceCents,
        'notaryFeesCents': scenario.notaryFeesCents,
        'worksInitialCents': scenario.worksInitialCents,
        'isNewProperty': scenario.isNewProperty,
        'downPaymentCents': scenario.downPaymentCents,
        'loanPrincipalCents': scenario.loanPrincipalCents,
        'loanRateBps': scenario.loanRateBps,
        'loanDurationMonths': scenario.loanDurationMonths,
        'monthlyRentHcCents': scenario.monthlyRentHcCents,
        'propertyTaxAnnualCents': scenario.propertyTaxAnnualCents,
        'insurancePnoAnnualCents': scenario.insurancePnoAnnualCents,
        'condoFeesNonRecoverableCents': scenario.condoFeesNonRecoverableCents,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final ref = _col.doc(scenario.id);
    await ref.update(payload);
    final saved = await ref.get();
    if (!saved.exists) {
      throw InvestmentScenarioNotFoundException(scenario.id);
    }
    return InvestmentScenario.fromJson(
      firestoreDocToSnakeJson(saved.data()!, docId: saved.id),
    );
  }

  @override
  Future<void> softDelete(String id) async {
    _log.info('softDelete($id)');
    await _functions.httpsCallable('softDeleteEntity').call(<String, dynamic>{
      'collection': 'investment_scenarios',
      'id': id,
    });
  }
}

class InvestmentScenarioNotFoundException implements Exception {
  const InvestmentScenarioNotFoundException(this.id);
  final String id;
  @override
  String toString() =>
      'InvestmentScenarioNotFoundException: scénario $id introuvable';
}

final investmentScenarioRepositoryProvider =
    Provider<InvestmentScenarioRepository>(
      (ref) => FirestoreInvestmentScenarioRepository(
        FirebaseFirestore.instance,
        FirebaseAuth.instance,
        FirebaseFunctions.instanceFor(region: 'europe-west1'),
      ),
    );

class InvestmentScenariosListNotifier
    extends AsyncNotifier<List<InvestmentScenario>> {
  @override
  Future<List<InvestmentScenario>> build() =>
      ref.read(investmentScenarioRepositoryProvider).list();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(investmentScenarioRepositoryProvider).list(),
    );
  }

  Future<void> delete(String id) async {
    await ref.read(investmentScenarioRepositoryProvider).softDelete(id);
    await reload();
  }
}

final investmentScenariosListProvider =
    AsyncNotifierProvider<
      InvestmentScenariosListNotifier,
      List<InvestmentScenario>
    >(InvestmentScenariosListNotifier.new);
