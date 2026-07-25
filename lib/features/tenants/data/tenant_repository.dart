import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';
import '../../../core/firestore_helpers.dart';
import '../../../core/utils/french_date.dart';
import '../domain/tenant.dart';
import '../domain/tenant_list_item.dart';

final _log = Logger('TenantRepository');

/// Contrat public du repository locataires.
abstract interface class TenantRepository {
  /// Liste tous les locataires du landlord courant, triés `lastName ASC, firstName ASC`.
  Future<List<Tenant>> list();

  /// Retourne un locataire par son [id].
  Future<Tenant> getById(String id);

  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    DateTime? birthDate,
    String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    int? monthlyIncomeCents,
    String? previousAddress,
    String? guarantorName,
    String? guarantorEmail,
    String? guarantorPhone,
  });

  Future<Tenant> update(Tenant tenant);

  Future<int> countActiveLeases(String tenantId);

  Future<void> archive(String id);

  /// Liste les locataires enrichis avec leur bail actif.
  ///
  /// 2 queries parallèles (tenants + leases actifs), jointure côté client.
  /// Les leases ont déjà les denorms propertyName/Address.
  Future<List<TenantListItem>> listWithActiveLeases();

  /// Liste les baux non-archivés d'un locataire (modèle Map brut — sera
  /// remplacé par Lease typé en Phase 3c lors de la migration LeaseRepo).
  Future<List<Map<String, dynamic>>> listLeasesForTenant(String tenantId);
}

class FirestoreTenantRepository implements TenantRepository {
  FirestoreTenantRepository(this._firestore, this._auth, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — tenant operations require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('tenants');

  @override
  Future<List<Tenant>> list() async {
    _log.info('list()');
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('deletedAt', isNull: true)
        .orderBy('lastName')
        .limit(200)
        .get();
    return qs.docs
        .map(
          (d) =>
              Tenant.fromJson(firestoreDocToSnakeJson(d.data(), docId: d.id)),
        )
        .toList();
  }

  @override
  Future<Tenant> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null || data['deletedAt'] != null) {
      throw TenantNotFoundException(id);
    }
    if (data['landlordId'] != _uid) {
      throw TenantNotFoundException(id);
    }
    return Tenant.fromJson(firestoreDocToSnakeJson(data, docId: snap.id));
  }

  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    DateTime? birthDate,
    String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    int? monthlyIncomeCents,
    String? previousAddress,
    String? guarantorName,
    String? guarantorEmail,
    String? guarantorPhone,
  }) async {
    _log.info('create()');
    // FEAT-044 : création via la Callable `createTenant` (plafond free-tier
    // imposé serveur + compteur landlord activeTenantsCount). Dates en ISO-8601
    // (les Timestamp ne transitent pas par le protocole Callable) ; le serveur
    // reconvertit + applique le trim/empty→null. Dépassement de plafond →
    // FirebaseFunctionsException(code: 'resource-exhausted').
    final callable = _functions.httpsCallable(
      'createTenant',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    final res = await callable.call(<String, dynamic>{
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'email': email.trim(),
      'phone': phone,
      'birthDate': birthDate?.toUtc().toIso8601String(),
      'birthPlace': birthPlace,
      'nationality': nationality,
      'profession': profession,
      'employer': employer,
      'monthlyIncomeCents': monthlyIncomeCents,
      'previousAddress': previousAddress,
      'guarantorName': guarantorName,
      'guarantorEmail': guarantorEmail,
      'guarantorPhone': guarantorPhone,
    });
    final tenantId = (res.data as Map?)?['tenantId'] as String?;
    if (tenantId == null) {
      throw StateError('createTenant did not return a tenantId');
    }
    return getById(tenantId);
  }

  @override
  Future<Tenant> update(Tenant tenant) async {
    _log.info('update(id=${tenant.id})');
    final birthDate = tenant.birthDate;
    final payload = <String, dynamic>{
      'firstName': tenant.firstName.trim(),
      'lastName': tenant.lastName.trim(),
      'email': tenant.email.trim(),
      'phone': _orNull(tenant.phone),
      'birthDate': birthDate == null
          ? null
          : Timestamp.fromDate(birthDate.toUtc()),
      'birthPlace': _orNull(tenant.birthPlace),
      'nationality': _orNull(tenant.nationality),
      'profession': _orNull(tenant.profession),
      'employer': _orNull(tenant.employer),
      'monthlyIncomeCents': tenant.monthlyIncomeCents,
      'previousAddress': _orNull(tenant.previousAddress),
      'guarantorName': _orNull(tenant.guarantorName),
      'guarantorEmail': _orNull(tenant.guarantorEmail),
      'guarantorPhone': _orNull(tenant.guarantorPhone),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final ref = _col.doc(tenant.id);
    await ref.update(payload);
    final saved = await ref.get();
    if (!saved.exists) {
      throw TenantNotFoundException(tenant.id);
    }
    return Tenant.fromJson(
      firestoreDocToSnakeJson(saved.data()!, docId: saved.id),
    );
  }

  @override
  Future<int> countActiveLeases(String tenantId) async {
    _log.info('countActiveLeases($tenantId)');
    final snap = await _col.doc(tenantId).get();
    if (!snap.exists) return 0;
    final count = snap.data()?['activeLeaseCount'];
    return count is int ? count : 0;
  }

  @override
  Future<void> archive(String id) async {
    _log.info('archive($id)');
    final callable = _functions.httpsCallable(
      'softDeleteEntity',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    await callable.call(<String, dynamic>{'collection': 'tenants', 'id': id});
  }

  @override
  Future<List<TenantListItem>> listWithActiveLeases() async {
    _log.info('listWithActiveLeases()');
    final uid = _uid;
    final tenantsQs = _col
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .orderBy('lastName')
        .limit(200)
        .get();
    final leasesQs = _firestore
        .collection('leases')
        .where('landlordId', isEqualTo: uid)
        .where('deletedAt', isNull: true)
        .where('status', isEqualTo: 'active')
        .get();

    final results = await Future.wait([tenantsQs, leasesQs]);
    final tenantDocs = results[0].docs;
    final leaseDocs = results[1].docs;

    // Index par tenantId — si plusieurs actifs, garde celui au startDate le plus récent.
    final activeByTenantId = <String, Map<String, dynamic>>{};
    for (final lease in leaseDocs) {
      final data = lease.data();
      final tenantId = data['tenantId'] as String?;
      if (tenantId == null) continue;
      final existing = activeByTenantId[tenantId];
      if (existing == null) {
        activeByTenantId[tenantId] = {...data, 'id': lease.id};
        continue;
      }
      final newStart =
          (data['startDate'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final oldStart =
          (existing['startDate'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      if (newStart > oldStart) {
        activeByTenantId[tenantId] = {...data, 'id': lease.id};
      }
    }

    return tenantDocs.map((doc) {
      final tenant = Tenant.fromJson(
        firestoreDocToSnakeJson(doc.data(), docId: doc.id),
      );
      final lease = activeByTenantId[doc.id];
      if (lease == null) return TenantListItem(tenant: tenant);

      final startDate = lease['startDate'] as Timestamp?;
      final endDate = lease['endDate'] as Timestamp?;
      String? periodLabel;
      if (startDate != null) {
        // format() (heure locale) directement depuis le Timestamp — le
        // détour par toUtc().toIso8601String() affichait un fragment ISO
        // (« 30T22:00:00.000Z/06/2026 ») et le jour UTC, veille du jour
        // réellement choisi.
        final startStr = FrenchDate.format(startDate.toDate());
        if (endDate == null) {
          periodLabel = 'Depuis $startStr';
        } else {
          periodLabel = '$startStr → ${FrenchDate.format(endDate.toDate())}';
        }
      }

      return TenantListItem(
        tenant: tenant,
        activeLeaseId: lease['id'] as String?,
        currentPropertyName: lease['propertyName'] as String?,
        activeLeasePeriodLabel: periodLabel,
        activeLeaseRentCents: lease['rentAmountCents'] as int?,
      );
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async {
    _log.info('listLeasesForTenant($tenantId)');
    final qs = await _firestore
        .collection('leases')
        .where('landlordId', isEqualTo: _uid)
        .where('tenantId', isEqualTo: tenantId)
        .where('deletedAt', isNull: true)
        .orderBy('startDate', descending: true)
        .get();

    return qs.docs.map((d) {
      final raw = d.data();
      // Aligne le format avec ce que les consommateurs attendaient
      // (snake_case + ISO strings).
      return {
        'id': d.id,
        'property_id': raw['propertyId'],
        'start_date': (raw['startDate'] as Timestamp?)
            ?.toDate()
            .toUtc()
            .toIso8601String(),
        'end_date': (raw['endDate'] as Timestamp?)
            ?.toDate()
            .toUtc()
            .toIso8601String(),
        'status': raw['status'],
        'rent_amount_cents': raw['rentAmountCents'],
      };
    }).toList();
  }
}

String? _orNull(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}

class TenantNotFoundException implements Exception {
  const TenantNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'TenantNotFoundException: locataire $id introuvable';
}

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return FirestoreTenantRepository(
    ref.watch(firestoreProvider),
    FirebaseAuth.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});
