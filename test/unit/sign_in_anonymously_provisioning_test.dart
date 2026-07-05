import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// BAILLAN-M1 — provisioning client du doc landlords/{uid} anonyme.
//
// Identity Platform est désactivé sur le projet : la CF handleNewUser
// (beforeUserCreated) ne se déclenche jamais. C'est donc signInAnonymously()
// qui doit créer le doc landlord (chemin CREATE anonyme des rules), sinon
// landlordTierProvider rend null et le renewer d'expiration échoue en
// NOT_FOUND en boucle.
// ---------------------------------------------------------------------------

void main() {
  group('FirebaseAuthRepository.signInAnonymously — provisioning', () {
    test('crée landlords/{uid} avec le payload anonyme complet', () async {
      final anonUser = MockUser(isAnonymous: true, uid: 'anon-prov-1');
      final auth = MockFirebaseAuth(mockUser: anonUser);
      final firestore = FakeFirebaseFirestore();
      final repo = FirebaseAuthRepository(auth, firestore);

      final before = DateTime.now();
      await repo.signInAnonymously();
      final after = DateTime.now();

      final snap = await firestore.doc('landlords/anon-prov-1').get();
      expect(snap.exists, isTrue);

      final data = snap.data()!;
      expect(data['id'], 'anon-prov-1');
      expect(data['email'], isNull);
      expect(data['fullName'], '');
      expect(data['isAnonymous'], isTrue);
      expect(data['subscriptionTier'], 'anonymous');
      expect(data['rgpdConsentAt'], isNull);
      expect(data['rgpdConsentVersion'], isNull);
      expect(data['deletedAt'], isNull);

      // anonExpiresAt = now + 14 jours (horloge client, timestamp concret —
      // la rule UPDATE borne à now + 15 jours max).
      final expiresAt = (data['anonExpiresAt'] as Timestamp).toDate();
      expect(
        expiresAt.isAfter(before.add(const Duration(days: 13))),
        isTrue,
        reason: 'anonExpiresAt doit être ~14 jours dans le futur',
      );
      expect(
        expiresAt.isBefore(after.add(const Duration(days: 15))),
        isTrue,
        reason: 'anonExpiresAt ne doit pas dépasser la borne des rules',
      );
    });

    test('ne réécrit pas un doc landlord déjà existant', () async {
      final anonUser = MockUser(isAnonymous: true, uid: 'anon-prov-2');
      final auth = MockFirebaseAuth(mockUser: anonUser);
      final firestore = FakeFirebaseFirestore();

      // Doc pré-existant : session anonyme réutilisée (reload d'app). Le
      // anonExpiresAt sentinel ne doit PAS être écrasé par un re-sign-in
      // (c'est le rôle exclusif du AnonExpiryRenewer).
      final sentinel = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 2)),
      );
      await firestore.doc('landlords/anon-prov-2').set({
        'id': 'anon-prov-2',
        'email': null,
        'fullName': '',
        'isAnonymous': true,
        'subscriptionTier': 'anonymous',
        'anonExpiresAt': sentinel,
        'rgpdConsentAt': null,
        'deletedAt': null,
      });

      final repo = FirebaseAuthRepository(auth, firestore);
      await repo.signInAnonymously();

      final snap = await firestore.doc('landlords/anon-prov-2').get();
      expect(snap.data()!['anonExpiresAt'], sentinel);
    });
  });

  group('FirebaseAuthRepository — payloads signup non-anonymes', () {
    test(
      'signUpWithPassword écrit isAnonymous=false + subscriptionTier=free',
      () async {
        final auth = MockFirebaseAuth();
        final firestore = FakeFirebaseFirestore();
        final repo = FirebaseAuthRepository(auth, firestore);

        await repo.signUpWithPassword(
          email: 'jean@exemple.fr',
          password: 'motdepasse1',
          fullName: 'Jean Dupont',
        );

        final docs = await firestore.collection('landlords').get();
        expect(docs.docs, hasLength(1));

        // La rule CREATE (compte complet) exige isAnonymous == false dans le
        // payload ; la rule UPDATE exige que subscriptionTier existe sur le
        // doc (comparaison d'égalité) — sans ces champs, signup et édition
        // de profil sont refusés par Firestore.
        final data = docs.docs.single.data();
        expect(data['isAnonymous'], isFalse);
        expect(data['subscriptionTier'], 'free');
        expect(data['anonExpiresAt'], isNull);
      },
    );
  });
}
