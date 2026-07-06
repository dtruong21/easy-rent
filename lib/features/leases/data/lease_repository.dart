import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/firestore_helpers.dart';
import '../../payments/domain/payment.dart';
import '../../payments/domain/payment_method.dart';
import '../domain/charge_mode.dart';
import '../domain/lease.dart';
import '../domain/lease_lateness.dart';
import '../domain/lease_list_item.dart';
import '../domain/lease_status.dart';
import '../domain/lease_type.dart';

final _log = Logger('LeaseRepository');

/// Contrat public du repository baux.
abstract interface class LeaseRepository {
  /// Liste tous les baux du landlord courant pour l'affichage.
  ///
  /// Tri : `status ASC` (active d'abord) puis `startDate DESC`. Les denorms
  /// `propertyName` et `tenant{First,Last}Name` sont déjà sur le doc lease,
  /// donc pas de jointure nécessaire (1 seule query).
  ///
  /// [now] est injectable pour les tests (calcul `isLate` déterministe,
  /// cf. `lease_lateness.dart`) — les appelants prod ne le fournissent
  /// jamais et obtiennent le défaut `DateTime.now()`.
  Future<List<LeaseListItem>> listForDisplay({DateTime? now});

  Future<Lease> getById(String id);

  /// Crée un nouveau bail via la Callable `createLease` (validation
  /// cross-entity property/tenant ownership + denorm snapshot + maintien
  /// activeLeaseCount sur property/tenant).
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    LeaseType leaseType,
    ChargeMode? chargeMode,
    int? depositAmountCents,
    int paymentDay,
    PaymentMethod paymentMethod,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents,
    bool solidarityClause,
    bool entryInventoryDone,
    int nonRecoverableChargesCents,
  });

  /// Met à jour via la Callable `updateLease` (whitelist champs mutables +
  /// maintien activeLeaseCount sur transition status).
  Future<Lease> update(Lease lease);

  /// Clôture un bail actif : status → terminated, endDate = effectiveEndDate.
  ///
  /// Implémenté comme un updateLease avec status='terminated' + endDate.
  /// La Callable maintient activeLeaseCount transactionnellement.
  Future<Lease> close(String id, {required DateTime effectiveEndDate});

  /// Vérifie qu'aucun autre bail actif n'existe pour ce propertyId.
  ///
  /// Implémentation : `properties.activeLeaseCount` lu côté client (denorm) ;
  /// si excludeLeaseId vise un bail actif sur ce property, on déduit -1.
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  });

  /// Archive (soft-delete) via la Callable `softDeleteEntity`.
  Future<void> archive(String id);
}

class FirestoreLeaseRepository implements LeaseRepository {
  FirestoreLeaseRepository(this._firestore, this._auth, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — lease operations require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('leases');

  HttpsCallable _callable(String name) => _functions.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
  );

  @override
  Future<List<LeaseListItem>> listForDisplay({DateTime? now}) async {
    _log.info('listForDisplay()');
    // Tri côté serveur : startDate DESC. Le tri status ASC (active d'abord)
    // est appliqué côté client après lecture pour ne pas multiplier les
    // indexes composites.
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('deletedAt', isNull: true)
        .orderBy('startDate', descending: true)
        .limit(200)
        .get();

    final leases = qs.docs
        .map(
          (d) => Lease.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)),
        )
        .toList();

    // FEAT-028 : le retard de paiement (pastille + filtre `late`) ne
    // concerne que les baux actifs — pas la peine de charger les paiements
    // des baux terminés/archivés (isLeaseLate() renvoie false direct dessus).
    final activeLeaseIds = leases
        .where((l) => l.status == LeaseStatus.active)
        .map((l) => l.id)
        .toList();
    final paymentsByLease = await _fetchPaymentsByLease(activeLeaseIds);

    final effectiveNow = now ?? DateTime.now();
    final items = qs.docs.map((d) {
      final lease = leases.firstWhere((l) => l.id == d.id);
      final data = d.data();
      final propertyName =
          (data['propertyName'] as String?) ?? '(bien archivé)';
      final firstName = (data['tenantFirstName'] as String?) ?? '';
      final lastName = (data['tenantLastName'] as String?) ?? '';
      final tenantDisplayName = firstName.isEmpty && lastName.isEmpty
          ? '(locataire archivé)'
          : '$firstName $lastName'.trim();
      final isLate = isLeaseLate(
        lease: lease,
        payments: paymentsByLease[lease.id] ?? const [],
        now: effectiveNow,
      );
      return LeaseListItem(
        lease: lease,
        propertyName: propertyName,
        tenantDisplayName: tenantDisplayName,
        isLate: isLate,
      );
    }).toList();

    // Tri secondaire status ASC (active d'abord puis terminated/archived).
    items.sort((a, b) {
      final sa = a.lease.status.name;
      final sb = b.lease.status.name;
      return sa.compareTo(sb);
    });
    return items;
  }

  /// Charge tous les paiements (non soft-supprimés) des baux [leaseIds],
  /// groupés par `leaseId`.
  ///
  /// Firestore ne supporte pas `whereIn` avec >30 valeurs — on chunke, comme
  /// le fait déjà `DashboardRepository.fetchRetards()`. Filtrage du
  /// recouvrement d'intervalle (`periodStart`/`periodEnd`) fait côté client
  /// par `isLeaseLate()` — pas de nouvel index composite requis.
  ///
  /// TODO(P2) : charge actuellement TOUT l'historique de paiements de
  /// chaque bail actif (pas de borne temporelle) — OK pour le MVP (volume
  /// faible par bail), mais coûteux en lectures Firestore si un portefeuille
  /// grossit avec des baux anciens ayant des dizaines de paiements alors que
  /// seul le mois dû courant (± quelques mois de marge pour le recouvrement
  /// d'intervalle) importe pour `isLeaseLate()`. Borner avec un filtre
  /// `periodEnd >= début du mois dû − marge` quand le volume le justifiera.
  Future<Map<String, List<Payment>>> _fetchPaymentsByLease(
    List<String> leaseIds,
  ) async {
    final result = <String, List<Payment>>{};
    if (leaseIds.isEmpty) return result;

    for (var i = 0; i < leaseIds.length; i += 30) {
      final chunk = leaseIds.sublist(
        i,
        i + 30 > leaseIds.length ? leaseIds.length : i + 30,
      );
      final paymentsQs = await _firestore
          .collection('payments')
          .where('landlordId', isEqualTo: _uid)
          .where('deletedAt', isNull: true)
          .where('leaseId', whereIn: chunk)
          .get();
      for (final d in paymentsQs.docs) {
        final payment = Payment.fromJson(
          firestoreDocToSnakeJson(d.data(), docId: d.id),
        );
        result.putIfAbsent(payment.leaseId, () => []).add(payment);
      }
    }
    return result;
  }

  @override
  Future<Lease> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['deletedAt'] != null) {
      throw LeaseNotFoundException(id);
    }
    if (data['landlordId'] != _uid) {
      throw LeaseNotFoundException(id);
    }
    return Lease.fromJson(firestoreDocToSnakeJson(data, docId: snap.id));
  }

  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    LeaseType leaseType = LeaseType.unfurnished,
    ChargeMode? chargeMode,
    int? depositAmountCents,
    int paymentDay = 1,
    PaymentMethod paymentMethod = PaymentMethod.virement,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents = 0,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
    int nonRecoverableChargesCents = 0,
  }) async {
    _log.info('create(propertyId=$propertyId, tenantId=$tenantId)');
    final res = await _callable('createLease').call(<String, dynamic>{
      'propertyId': propertyId,
      'tenantId': tenantId,
      'rentAmountCents': rentAmountCents,
      'chargesAmountCents': chargesAmountCents,
      'nonRecoverableChargesCents': nonRecoverableChargesCents,
      'startDate': startDate.toUtc().toIso8601String(),
      'endDate': ?endDate?.toUtc().toIso8601String(),
      'status': 'active',
      'leaseType': leaseType.sqlValue,
      // FEAT-042 : omis si null pour laisser le serveur dériver le défaut
      // cohérent avec `leaseType` (`resolveChargeMode` dans lease_payment.ts).
      'chargeMode': ?chargeMode?.sqlValue,
      'depositAmountCents': ?depositAmountCents,
      'paymentDay': paymentDay,
      'paymentMethod': paymentMethod.sqlValue,
      'irlIndexValue': ?irlIndexValue,
      'irlQuarterRef': ?irlQuarterRef,
      'agencyFeesCents': agencyFeesCents,
      'solidarityClause': solidarityClause,
      'entryInventoryDone': entryInventoryDone,
    });
    final leaseId = (res.data as Map?)?['leaseId'] as String?;
    if (leaseId == null) {
      throw StateError('createLease did not return a leaseId');
    }
    return getById(leaseId);
  }

  @override
  Future<Lease> update(Lease lease) async {
    _log.info('update(id=${lease.id})');
    final patch = <String, dynamic>{
      'rentAmountCents': lease.rentAmountCents,
      'chargesAmountCents': lease.chargesAmountCents,
      'nonRecoverableChargesCents': lease.nonRecoverableChargesCents,
      'endDate': lease.endDate?.toUtc().toIso8601String(),
      'leaseType': lease.leaseType.sqlValue,
      // FEAT-042 : `null` reste possible (bail pré-042 non modifié) — le
      // serveur recoerce la cohérence type↔mode sur l'état final.
      'chargeMode': lease.chargeMode?.sqlValue,
      'depositAmountCents': lease.depositAmountCents,
      'paymentDay': lease.paymentDay,
      'paymentMethod': lease.paymentMethod.sqlValue,
      'irlIndexValue': lease.irlIndexValue,
      'irlQuarterRef': lease.irlQuarterRef,
      'agencyFeesCents': lease.agencyFeesCents,
      'solidarityClause': lease.solidarityClause,
      'entryInventoryDone': lease.entryInventoryDone,
    };
    await _callable(
      'updateLease',
    ).call(<String, dynamic>{'id': lease.id, 'patch': patch});
    return getById(lease.id);
  }

  @override
  Future<Lease> close(String id, {required DateTime effectiveEndDate}) async {
    _log.info('close(id=$id)');
    final current = await getById(id);
    if (current.status.name != 'active') {
      throw LeaseAlreadyClosedException(id);
    }
    await _callable('updateLease').call(<String, dynamic>{
      'id': id,
      'patch': <String, dynamic>{
        'status': 'terminated',
        'endDate': effectiveEndDate.toUtc().toIso8601String(),
      },
    });
    return getById(id);
  }

  @override
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  }) async {
    _log.info(
      'hasOtherActiveLeaseOnProperty($propertyId, exclude=$excludeLeaseId)',
    );
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('propertyId', isEqualTo: propertyId)
        .where('deletedAt', isNull: true)
        .where('status', isEqualTo: 'active')
        .limit(2)
        .get();

    for (final doc in qs.docs) {
      if (doc.id != excludeLeaseId) return true;
    }
    return false;
  }

  @override
  Future<void> archive(String id) async {
    _log.info('archive($id)');
    await _callable(
      'softDeleteEntity',
    ).call(<String, dynamic>{'collection': 'leases', 'id': id});
  }
}

class LeaseNotFoundException implements Exception {
  const LeaseNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'LeaseNotFoundException: bail $id introuvable';
}

class LeaseAlreadyClosedException implements Exception {
  const LeaseAlreadyClosedException(this.id);
  final String id;
  @override
  String toString() =>
      'LeaseAlreadyClosedException: bail $id déjà clôturé ou introuvable';
}

final leaseRepositoryProvider = Provider<LeaseRepository>((ref) {
  return FirestoreLeaseRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});
