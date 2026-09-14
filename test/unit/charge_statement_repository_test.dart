/// Test du mapping [FirestoreChargeStatementRepository.listForLease] via
/// [FakeFirebaseFirestore] (package `fake_cloud_firestore`).
///
/// Les callables (`finalize`/`voidStatement`/`markAsSent`) nécessitent un mock
/// `FirebaseFunctions` — leur logique vit côté serveur (Tasks 1-2) ; seule la
/// lecture/mapping est testée ici, comme pour `receipts_repository_test.dart`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:easyrent/features/charge_regularization/data/charge_statement_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FirebaseFunctions] jamais appelé par `listForLease` — toute utilisation
/// lève via noSuchMethod (pattern `receipts_repository_payment_notes_test.dart`).
class _UnusedFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FirestoreChargeStatementRepository.listForLease', () {
    Future<Map<String, dynamic>> baseDoc({
      required String id,
      required String leaseId,
      required DateTime createdAt,
      int balanceCents = 3000,
    }) async => {
      'id': id,
      'landlordId': 'lord1',
      'leaseId': leaseId,
      'propertyId': 'p1',
      'landlordFullName': 'J',
      'landlordAddress': 'A',
      'tenantFullName': 'M Loc',
      'tenantFirstName': 'M',
      'propertyName': 'S',
      'propertyAddress': 'B',
      'periodStart': Timestamp.fromDate(DateTime.utc(2025, 1, 1)),
      'periodEnd': Timestamp.fromDate(DateTime.utc(2025, 12, 31)),
      'provisionsCollectedCents': 12000,
      'actualExpensesCents': 15000,
      'actualExpensesSource': 'manual',
      'balanceCents': balanceCents,
      'lineItems': [],
      'createdAt': Timestamp.fromDate(createdAt),
      'isVoided': false,
      'voidedAt': null,
      'voidedReason': null,
      'sentAt': null,
      'sentToEmail': null,
      'schemaVersion': 1,
    };

    test('relit et mappe un décompte', () async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('charge_statements')
          .doc('cs-1')
          .set(
            await baseDoc(
              id: 'cs-1',
              leaseId: 'l1',
              createdAt: DateTime.utc(2026, 1, 5),
            ),
          );
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'lord1'),
      );
      final repo = FirestoreChargeStatementRepository(
        fs,
        auth,
        _UnusedFunctions(),
      );

      final list = await repo.listForLease('l1');

      expect(list, hasLength(1));
      expect(list.single.id, 'cs-1');
      expect(list.single.balanceCents, 3000);
      expect(list.single.leaseId, 'l1');
      expect(list.single.landlordId, 'lord1');
    });

    test('filtre par leaseId', () async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('charge_statements')
          .doc('cs-1')
          .set(
            await baseDoc(
              id: 'cs-1',
              leaseId: 'l1',
              createdAt: DateTime.utc(2026, 1, 5),
            ),
          );
      await fs
          .collection('charge_statements')
          .doc('cs-2')
          .set(
            await baseDoc(
              id: 'cs-2',
              leaseId: 'l2',
              createdAt: DateTime.utc(2026, 1, 6),
            ),
          );
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'lord1'),
      );
      final repo = FirestoreChargeStatementRepository(
        fs,
        auth,
        _UnusedFunctions(),
      );

      final list = await repo.listForLease('l1');

      expect(list, hasLength(1));
      expect(list.single.id, 'cs-1');
    });

    test('trie par createdAt DESC', () async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('charge_statements')
          .doc('cs-old')
          .set(
            await baseDoc(
              id: 'cs-old',
              leaseId: 'l1',
              createdAt: DateTime.utc(2025, 1, 1),
              balanceCents: 1000,
            ),
          );
      await fs
          .collection('charge_statements')
          .doc('cs-new')
          .set(
            await baseDoc(
              id: 'cs-new',
              leaseId: 'l1',
              createdAt: DateTime.utc(2026, 1, 1),
              balanceCents: 2000,
            ),
          );
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'lord1'),
      );
      final repo = FirestoreChargeStatementRepository(
        fs,
        auth,
        _UnusedFunctions(),
      );

      final list = await repo.listForLease('l1');

      expect(list, hasLength(2));
      expect(list.first.id, 'cs-new');
      expect(list.last.id, 'cs-old');
    });
  });
}
