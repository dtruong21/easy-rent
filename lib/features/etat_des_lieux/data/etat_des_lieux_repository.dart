import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/config/firestore_provider.dart';
import '../../../core/firestore_helpers.dart';
import '../domain/edl_enums.dart';
import '../domain/etat_des_lieux.dart';

final _log = Logger('EtatDesLieuxRepository');

abstract interface class EtatDesLieuxRepository {
  /// Crée un état des lieux via la Callable `createEtatDesLieux` (FEAT-037).
  ///
  /// La CF fige `landlordFullName`/`landlordAddress` (profil bailleur) et
  /// `tenantFullName`/`propertyAddress` (bail) — ces champs ne sont PAS
  /// envoyés ici, ils sont dérivés côté serveur (immuabilité légale, décret
  /// 2016-382).
  Future<EtatDesLieux> create({
    required String leaseId,
    required EtatDesLieuxType type,
    required DateTime date,
    required List<EdlRoom> rooms,
    required EdlMeterReadings meterReadings,
    required int keysCount,
    String? generalComment,
  });

  Future<List<EtatDesLieux>> listForLease(String leaseId);

  Future<EtatDesLieux> getById(String id);
}

class FirestoreEtatDesLieuxRepository implements EtatDesLieuxRepository {
  FirestoreEtatDesLieuxRepository(this._firestore, this._auth, this._functions);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated — EDL operations require auth');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('etat_des_lieux');

  HttpsCallable _callable(String name) => _functions.httpsCallable(
    name,
    options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
  );

  @override
  Future<EtatDesLieux> create({
    required String leaseId,
    required EtatDesLieuxType type,
    required DateTime date,
    required List<EdlRoom> rooms,
    required EdlMeterReadings meterReadings,
    required int keysCount,
    String? generalComment,
  }) async {
    _log.info('create(leaseId=$leaseId, type=${type.sqlValue})');
    final res = await _callable('createEtatDesLieux').call(<String, dynamic>{
      'leaseId': leaseId,
      'type': type.sqlValue,
      'date': date.toUtc().toIso8601String(),
      'rooms': rooms
          .map(
            (room) => <String, dynamic>{
              'name': room.name,
              'elements': room.elements
                  .map(
                    (el) => <String, dynamic>{
                      'name': el.name,
                      'condition': el.condition.sqlValue,
                      'comment': ?el.comment,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'meterReadings': <String, dynamic>{
        'waterIndex': ?meterReadings.waterIndex,
        'electricityIndex': ?meterReadings.electricityIndex,
        'gasIndex': ?meterReadings.gasIndex,
      },
      'keysCount': keysCount,
      'generalComment': ?generalComment,
    });
    final data = (res.data as Map?) ?? const {};
    final id = data['etatDesLieuxId'] as String?;
    if (id == null) {
      throw const EtatDesLieuxCreationException(
        'createEtatDesLieux did not return an etatDesLieuxId',
      );
    }
    return getById(id);
  }

  @override
  Future<List<EtatDesLieux>> listForLease(String leaseId) async {
    _log.info('listForLease(leaseId=$leaseId)');
    final qs = await _col
        .where('landlordId', isEqualTo: _uid)
        .where('leaseId', isEqualTo: leaseId)
        .orderBy('createdAt', descending: true)
        .get();
    return qs.docs
        .map(
          (d) => EtatDesLieux.fromJson(
            firestoreDocToSnakeJson(d.data(), docId: d.id),
          ),
        )
        .toList();
  }

  @override
  Future<EtatDesLieux> getById(String id) async {
    _log.info('getById($id)');
    final snap = await _col.doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null) {
      throw EtatDesLieuxNotFoundException(id);
    }
    if (data['landlordId'] != _uid) {
      throw EtatDesLieuxNotFoundException(id);
    }
    return EtatDesLieux.fromJson(firestoreDocToSnakeJson(data, docId: snap.id));
  }
}

class EtatDesLieuxNotFoundException implements Exception {
  const EtatDesLieuxNotFoundException(this.id);
  final String id;
  @override
  String toString() =>
      'EtatDesLieuxNotFoundException: état des lieux $id introuvable';
}

class EtatDesLieuxCreationException implements Exception {
  const EtatDesLieuxCreationException(this.message);
  final String message;
  @override
  String toString() => 'EtatDesLieuxCreationException: $message';
}

final etatDesLieuxRepositoryProvider = Provider<EtatDesLieuxRepository>((ref) {
  return FirestoreEtatDesLieuxRepository(
    ref.watch(firestoreProvider),
    FirebaseAuth.instance,
    FirebaseFunctions.instanceFor(region: 'europe-west1'),
  );
});
