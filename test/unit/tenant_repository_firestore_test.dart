/// Tests de [FirestoreTenantRepository.listWithActiveLeases] via
/// fake_cloud_firestore.
///
/// Couvre le libellé de période du bail actif (TenantCard) :
/// - CDI → « Depuis dd/MM/yyyy » en heure locale (régression
///   « Depuis 30T22:00:00.000Z/06/2026 » : détour Timestamp → ISO UTC →
///   formatIsoString qui n'attendait que YYYY-MM-DD)
/// - Bail avec fin → « dd/MM/yyyy → dd/MM/yyyy »
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FirebaseFunctions] jamais invoqué par listWithActiveLeases — toute
/// utilisation inattendue fait échouer le test.
class _UnusedFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FirebaseFunctions ne doit pas être appelé par listWithActiveLeases',
  );
}

void main() {
  const uid = 'landlord-1';

  late FakeFirebaseFirestore firestore;
  late FirestoreTenantRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
    repo = FirestoreTenantRepository(firestore, auth, _UnusedFunctions());
  });

  Future<void> seedTenant() async {
    await firestore.collection('tenants').doc('t1').set({
      'landlordId': uid,
      'firstName': 'David',
      'lastName': 'Truong',
      'email': 'david@exemple.fr',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'deletedAt': null,
    });
  }

  Future<void> seedActiveLease({DateTime? endDate, String? propertyId}) async {
    await firestore.collection('leases').doc('l1').set({
      'landlordId': uid,
      'tenantId': 't1',
      'status': 'active',
      'deletedAt': null,
      // Minuit LOCAL, comme saisi au date picker du formulaire bail.
      'startDate': Timestamp.fromDate(DateTime(2026, 7, 1)),
      if (endDate != null) 'endDate': Timestamp.fromDate(endDate),
      'propertyId': ?propertyId,
      'propertyName': 'Studio Hazay',
      'rentAmountCents': 65000,
    });
  }

  group('FirestoreTenantRepository.listWithActiveLeases — periodLabel', () {
    test(
      'bail CDI → « Depuis 01/07/2026 » (jour local, pas de fragment ISO)',
      () async {
        await seedTenant();
        await seedActiveLease();

        final items = await repo.listWithActiveLeases();

        expect(items, hasLength(1));
        final item = items.single;
        expect(item.activeLeasePeriodLabel, 'Depuis 01/07/2026');
        expect(item.currentPropertyName, 'Studio Hazay');
        expect(item.activeLeaseRentCents, 65000);
      },
    );

    test('bail avec fin → « 01/07/2026 → 30/06/2027 »', () async {
      await seedTenant();
      await seedActiveLease(endDate: DateTime(2027, 6, 30));

      final items = await repo.listWithActiveLeases();

      expect(items.single.activeLeasePeriodLabel, '01/07/2026 → 30/06/2027');
    });

    test('locataire sans bail actif → pas de libellé', () async {
      await seedTenant();

      final items = await repo.listWithActiveLeases();

      expect(items.single.activeLeasePeriodLabel, isNull);
      expect(items.single.activeLeaseId, isNull);
    });
  });

  group('FirestoreTenantRepository.listWithActiveLeases — '
      'currentPropertyColorKey (FEAT-057, lecture groupée)', () {
    test(
      'bien du bail actif avec colorKey → propagée sur le '
      'TenantListItem (pas de requête supplémentaire par locataire)',
      () async {
        await firestore.collection('properties').doc('p1').set({
          'landlordId': uid,
          'name': 'Studio Hazay',
          'address': '1 rue Hazay',
          'type': 'studio',
          'colorKey': 'prune',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'deletedAt': null,
        });
        await seedTenant();
        await seedActiveLease(propertyId: 'p1');

        final items = await repo.listWithActiveLeases();

        expect(items.single.currentPropertyId, 'p1');
        expect(items.single.currentPropertyColorKey, 'prune');
      },
    );

    test('bien sans colorKey (créé avant FEAT-057) → '
        'currentPropertyColorKey null (le repli déterministe se fait à '
        "l'affichage, pas ici)", () async {
      await firestore.collection('properties').doc('p1').set({
        'landlordId': uid,
        'name': 'Studio Hazay',
        'address': '1 rue Hazay',
        'type': 'studio',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'deletedAt': null,
      });
      await seedTenant();
      await seedActiveLease(propertyId: 'p1');

      final items = await repo.listWithActiveLeases();

      expect(items.single.currentPropertyColorKey, isNull);
    });

    test('locataire sans bail actif → currentPropertyId et '
        'currentPropertyColorKey null', () async {
      await seedTenant();

      final items = await repo.listWithActiveLeases();

      expect(items.single.currentPropertyId, isNull);
      expect(items.single.currentPropertyColorKey, isNull);
    });
  });
}
