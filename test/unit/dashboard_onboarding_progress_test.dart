import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uid = 'landlord-1';
  late FakeFirebaseFirestore db;
  late FirestoreDashboardRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreDashboardRepository(
      db,
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
    );
  });

  Future<void> seed(String col, Map<String, dynamic> data) =>
      db.collection(col).add({'landlordId': uid, 'deletedAt': null, ...data});

  test('compte vide → tout false, firstLeaseId null', () async {
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasProperty, isFalse);
    expect(p.hasReceipt, isFalse);
    expect(p.firstLeaseId, isNull);
    expect(p.isComplete, isFalse);
  });

  test('un bien seul → hasProperty true, reste false', () async {
    await seed('properties', {'name': 'B1'});
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasProperty, isTrue);
    expect(p.hasTenant, isFalse);
    expect(p.hasLease, isFalse);
  });

  test('un bail → firstLeaseId renseigné', () async {
    final ref = await db.collection('leases').add({
      'landlordId': uid,
      'deletedAt': null,
    });
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasLease, isTrue);
    expect(p.firstLeaseId, ref.id);
  });

  test('une quittance → isComplete true', () async {
    await db.collection('receipts').add({'landlordId': uid});
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasReceipt, isTrue);
    expect(p.isComplete, isTrue);
  });

  test('ignore les docs soft-deleted', () async {
    await db.collection('properties').add({
      'landlordId': uid,
      'deletedAt': Timestamp.now(),
    });
    final p = await repo.fetchOnboardingProgress();
    expect(p.hasProperty, isFalse);
  });
}
