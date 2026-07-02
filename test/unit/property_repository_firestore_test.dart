/// Tests de la VRAIE implémentation [FirestorePropertyRepository] contre
/// fake_cloud_firestore — en particulier l'exclusion des docs soft-deleted.
///
/// Les autres tests de repo du projet testent des fakes d'interface
/// in-memory : la couche query Firestore réelle n'était couverte nulle part,
/// ce qui a laissé passer le no-op `isEqualTo: null` (cf.
/// firestore_query_conformance_test.dart pour le verrou source — le fake
/// filtre null même avec l'ancienne syntaxe, ce test seul n'aurait donc pas
/// suffi à attraper la régression, mais il verrouille la sémantique métier).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FirebaseFunctions] jamais appelé par les chemins list/get testés ici —
/// toute utilisation lève via noSuchMethod.
class _UnusedFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _uid = 'lld-test-1';

Map<String, dynamic> _propertyDoc({
  required String landlordId,
  required String name,
  DateTime? deletedAt,
  DateTime? createdAt,
}) => {
  'landlordId': landlordId,
  'name': name,
  'address': '1 rue de la Paix, 75001 Paris',
  'type': 'studio',
  'deletedAt': deletedAt == null ? null : Timestamp.fromDate(deletedAt),
  'createdAt': Timestamp.fromDate(createdAt ?? DateTime.utc(2026, 1, 1)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
};

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestorePropertyRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _uid, isAnonymous: false, isEmailVerified: true),
    );
    repo = FirestorePropertyRepository(firestore, auth, _UnusedFunctions());
  });

  group('FirestorePropertyRepository — exclusion soft-delete + isolation', () {
    test(
      'list() exclut les biens soft-deleted et ceux des autres landlords',
      () async {
        await firestore
            .collection('properties')
            .doc('p-live')
            .set(_propertyDoc(landlordId: _uid, name: 'Bien vivant'));
        await firestore
            .collection('properties')
            .doc('p-deleted')
            .set(
              _propertyDoc(
                landlordId: _uid,
                name: 'Bien archivé',
                deletedAt: DateTime.utc(2026, 6, 1),
              ),
            );
        await firestore
            .collection('properties')
            .doc('p-other')
            .set(
              _propertyDoc(
                landlordId: 'autre-landlord',
                name: 'Bien d\'autrui',
              ),
            );

        final result = await repo.list();

        expect(result, hasLength(1));
        expect(result.single.name, 'Bien vivant');
      },
    );

    test('listWithLeases() exclut les biens soft-deleted', () async {
      await firestore
          .collection('properties')
          .doc('p-live')
          .set(_propertyDoc(landlordId: _uid, name: 'Bien vivant'));
      await firestore
          .collection('properties')
          .doc('p-deleted')
          .set(
            _propertyDoc(
              landlordId: _uid,
              name: 'Bien archivé',
              deletedAt: DateTime.utc(2026, 6, 1),
            ),
          );

      final result = await repo.listWithLeases();

      expect(result, hasLength(1));
      expect(result.single.property.name, 'Bien vivant');
    });

    test('list() trie createdAt DESC', () async {
      await firestore
          .collection('properties')
          .doc('p-old')
          .set(
            _propertyDoc(
              landlordId: _uid,
              name: 'Ancien',
              createdAt: DateTime.utc(2025, 1, 1),
            ),
          );
      await firestore
          .collection('properties')
          .doc('p-new')
          .set(
            _propertyDoc(
              landlordId: _uid,
              name: 'Récent',
              createdAt: DateTime.utc(2026, 6, 1),
            ),
          );

      final result = await repo.list();

      expect(result.map((p) => p.name).toList(), ['Récent', 'Ancien']);
    });
  });
}
