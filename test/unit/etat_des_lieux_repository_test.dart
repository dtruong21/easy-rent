/// Tests de la VRAIE implémentation [FirestoreEtatDesLieuxRepository] contre
/// fake_cloud_firestore + un [FirebaseFunctions] enregistreur — FEAT-037,
/// patron `investment_scenario_repository_firestore_test.dart`.
///
/// `fake_cloud_firestore` n'exécute aucune Cloud Function : [_RecordingFunctions]
/// simule donc, pour `createEtatDesLieux` uniquement, l'écriture serveur
/// (`functions/src/callable/etat_des_lieux.ts`) — lecture `landlords/{uid}` +
/// `leases/{leaseId}`, figeage des parties/adresse, écriture du doc — afin de
/// vérifier le contrat complet de `create()` (payload envoyé + hydratation du
/// modèle retourné), pas seulement le transport.
///
/// Ils ne peuvent PAS attraper un refus des règles de sécurité (la rule
/// `etat_des_lieux/create` vaut `if false` — fake_cloud_firestore n'évalue
/// jamais `firestore.rules`) ; c'est couvert ailleurs (émulateur / rules
/// tests).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/features/etat_des_lieux/data/etat_des_lieux_repository.dart';
import 'package:easyrent/features/etat_des_lieux/domain/edl_enums.dart';
import 'package:easyrent/features/etat_des_lieux/domain/etat_des_lieux.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FirebaseFunctions] qui simule, pour `createEtatDesLieux` seulement,
/// l'écriture serveur réelle (lecture landlord + lease, figeage, insert).
class _RecordingFunctions implements FirebaseFunctions {
  _RecordingFunctions(this._firestore, this._auth);

  final FakeFirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final List<String> invocations = <String>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _RecordingCallable(name, invocations, _firestore, _auth);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FirebaseFunctions.${invocation.memberName} non stubbé dans ce test',
  );
}

class _RecordingCallable implements HttpsCallable {
  _RecordingCallable(
    this._name,
    this._invocations,
    this._firestore,
    this._auth,
  );

  final String _name;
  final List<String> _invocations;
  final FakeFirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    _invocations.add(_name);

    if (_name != 'createEtatDesLieux') {
      return _FakeCallableResult<T>(null as T);
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      // Cf. investment_scenario_repository_firestore_test.dart :
      // FirebaseFunctionsException a un constructeur @protected —
      // StateError garde l'intention testée sans compromettre l'analyse.
      throw StateError('Not authenticated — cannot invoke createEtatDesLieux');
    }

    final data = Map<String, dynamic>.from(parameters! as Map);

    final landlordSnap = await _firestore.doc('landlords/$uid').get();
    final landlord = landlordSnap.data();
    if (landlord == null) {
      throw StateError('landlord not found');
    }
    final landlordFullName = (landlord['fullName'] as String?) ?? '';
    final landlordAddress = (landlord['address'] as String?) ?? '';
    if (landlordFullName.isEmpty || landlordAddress.isEmpty) {
      throw StateError('profile_incomplete');
    }

    final leaseId = data['leaseId'] as String;
    final leaseSnap = await _firestore.doc('leases/$leaseId').get();
    final lease = leaseSnap.data();
    if (lease == null) {
      throw StateError('lease not found');
    }
    if (lease['landlordId'] != uid) {
      throw StateError('lease not owned');
    }

    final tenantFullName =
        '${lease['tenantFirstName'] ?? ''} ${lease['tenantLastName'] ?? ''}'
            .trim();
    final propertyAddress = (lease['propertyAddress'] as String?) ?? '';

    final ref = _firestore.collection('etat_des_lieux').doc();
    await ref.set(<String, dynamic>{
      'id': ref.id,
      'landlordId': uid,
      'leaseId': leaseId,
      'propertyId': lease['propertyId'],
      'type': data['type'],
      'date': Timestamp.fromDate(DateTime.parse(data['date'] as String)),
      'propertyAddress': propertyAddress,
      'landlordFullName': landlordFullName,
      'landlordAddress': landlordAddress,
      'tenantFullName': tenantFullName,
      'rooms': data['rooms'],
      'meterReadings': data['meterReadings'],
      'keysCount': data['keysCount'],
      'generalComment': data['generalComment'],
      'createdAt': FieldValue.serverTimestamp(),
      'schemaVersion': 1,
    });
    return _FakeCallableResult<T>({'etatDesLieuxId': ref.id} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'HttpsCallable.${invocation.memberName} non stubbé dans ce test',
  );
}

class _FakeCallableResult<T> implements HttpsCallableResult<T> {
  _FakeCallableResult(this.data);

  @override
  final T data;
}

const _uid = 'landlord-edl-1';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late _RecordingFunctions functions;
  late FirestoreEtatDesLieuxRepository repo;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));
    functions = _RecordingFunctions(firestore, auth);
    repo = FirestoreEtatDesLieuxRepository(firestore, auth, functions);

    await firestore.doc('landlords/$_uid').set(<String, dynamic>{
      'fullName': 'Jean Bailleur',
      'address': '1 rue du Bailleur, 75001 Paris',
    });
    await firestore.doc('leases/lease-1').set(<String, dynamic>{
      'landlordId': _uid,
      'propertyId': 'prop-1',
      'tenantFirstName': 'Alice',
      'tenantLastName': 'Locataire',
      'propertyAddress': '2 rue du Locataire, 75002 Paris',
      'deletedAt': null,
    });
  });

  /// Sème un doc `etat_des_lieux/{id}` complet (tous les champs requis par
  /// `EtatDesLieux.fromJson`) — utilisé pour tester listForLease/getById
  /// sans passer par la callable.
  Future<void> seedEdl({
    required String id,
    String landlordId = _uid,
    String leaseId = 'lease-1',
    DateTime? createdAt,
  }) async {
    await firestore.collection('etat_des_lieux').doc(id).set(<String, dynamic>{
      'id': id,
      'landlordId': landlordId,
      'leaseId': leaseId,
      'propertyId': 'prop-1',
      'type': 'entree',
      'date': Timestamp.fromDate(DateTime(2026, 6, 1)),
      'propertyAddress': '2 rue du Locataire, 75002 Paris',
      'landlordFullName': 'Jean Bailleur',
      'landlordAddress': '1 rue du Bailleur, 75001 Paris',
      'tenantFullName': 'Alice Locataire',
      'rooms': <Map<String, dynamic>>[
        {
          'name': 'Salon',
          'elements': [
            {'name': 'Murs', 'condition': 'bon', 'comment': null},
          ],
        },
      ],
      'meterReadings': <String, dynamic>{
        'waterIndex': '1234',
        'electricityIndex': null,
        'gasIndex': null,
      },
      'keysCount': 2,
      'generalComment': null,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 6, 1)),
    });
  }

  group('FirestoreEtatDesLieuxRepository — create()', () {
    test('invoque createEtatDesLieux et hydrate le modèle retourné', () async {
      final created = await repo.create(
        leaseId: 'lease-1',
        type: EtatDesLieuxType.entree,
        date: DateTime.utc(2026, 6, 1),
        rooms: const [
          EdlRoom(
            name: 'Salon',
            elements: [EdlElement(name: 'Murs', condition: EdlCondition.bon)],
          ),
        ],
        meterReadings: const EdlMeterReadings(waterIndex: '1000'),
        keysCount: 2,
        generalComment: 'RAS',
      );

      expect(functions.invocations, ['createEtatDesLieux']);
      expect(created.id, isNotEmpty);
      expect(created.landlordId, _uid);
      expect(created.leaseId, 'lease-1');
      expect(created.type, EtatDesLieuxType.entree);
      // Figés côté serveur depuis landlord/lease — jamais envoyés par le repo.
      expect(created.landlordFullName, 'Jean Bailleur');
      expect(created.landlordAddress, '1 rue du Bailleur, 75001 Paris');
      expect(created.tenantFullName, 'Alice Locataire');
      expect(created.propertyAddress, '2 rue du Locataire, 75002 Paris');
      expect(created.rooms.single.name, 'Salon');
      expect(created.rooms.single.elements.single.condition, EdlCondition.bon);
      expect(created.meterReadings.waterIndex, '1000');
      expect(created.keysCount, 2);
      expect(created.generalComment, 'RAS');
    });

    test('envoie les enums en sqlValue (pas .name)', () async {
      await repo.create(
        leaseId: 'lease-1',
        type: EtatDesLieuxType.sortie,
        date: DateTime.utc(2026, 6, 1),
        rooms: const [
          EdlRoom(
            name: 'Cuisine',
            elements: [EdlElement(name: 'Sol', condition: EdlCondition.moyen)],
          ),
        ],
        meterReadings: const EdlMeterReadings(),
        keysCount: 1,
      );

      final stored = await firestore
          .collection('etat_des_lieux')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      final doc = stored.docs.single.data();
      expect(doc['type'], 'sortie');
      final rooms = doc['rooms'] as List;
      final elements = (rooms.single as Map)['elements'] as List;
      expect((elements.single as Map)['condition'], 'moyen');
    });

    test('échoue si non authentifié', () async {
      final anonAuth = MockFirebaseAuth(signedIn: false);
      final anonRepo = FirestoreEtatDesLieuxRepository(
        firestore,
        anonAuth,
        _RecordingFunctions(firestore, anonAuth),
      );
      expect(
        () => anonRepo.create(
          leaseId: 'lease-1',
          type: EtatDesLieuxType.entree,
          date: DateTime.utc(2026, 6, 1),
          rooms: const [],
          meterReadings: const EdlMeterReadings(),
          keysCount: 0,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FirestoreEtatDesLieuxRepository — listForLease()', () {
    test('retourne les EDL du bail, triés createdAt desc', () async {
      await seedEdl(id: 'edl-old', createdAt: DateTime(2026, 1, 1));
      await seedEdl(id: 'edl-new', createdAt: DateTime(2026, 3, 1));

      final result = await repo.listForLease('lease-1');

      expect(result.map((e) => e.id), ['edl-new', 'edl-old']);
    });

    test('owner-scopé : exclut les EDL d\'un autre landlord', () async {
      await seedEdl(id: 'edl-mine');
      await seedEdl(id: 'edl-other', landlordId: 'autre-landlord');

      final result = await repo.listForLease('lease-1');

      expect(result, hasLength(1));
      expect(result.single.id, 'edl-mine');
    });

    test('filtre par leaseId', () async {
      await seedEdl(id: 'edl-1', leaseId: 'lease-1');
      await seedEdl(id: 'edl-2', leaseId: 'lease-2');

      final result = await repo.listForLease('lease-1');

      expect(result, hasLength(1));
      expect(result.single.id, 'edl-1');
    });
  });

  group('FirestoreEtatDesLieuxRepository — getById()', () {
    test('retourne l\'EDL si trouvé et possédé', () async {
      await seedEdl(id: 'edl-42');

      final result = await repo.getById('edl-42');

      expect(result.id, 'edl-42');
      expect(result.landlordAddress, '1 rue du Bailleur, 75001 Paris');
    });

    test('lève EtatDesLieuxNotFoundException si introuvable', () async {
      expect(
        () => repo.getById('inconnu'),
        throwsA(isA<EtatDesLieuxNotFoundException>()),
      );
    });

    test(
      'lève EtatDesLieuxNotFoundException pour un EDL d\'un autre landlord',
      () async {
        await seedEdl(id: 'edl-foreign', landlordId: 'autre-landlord');

        expect(
          () => repo.getById('edl-foreign'),
          throwsA(isA<EtatDesLieuxNotFoundException>()),
        );
      },
    );
  });
}
