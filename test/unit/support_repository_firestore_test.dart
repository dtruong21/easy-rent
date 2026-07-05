/// Tests de la VRAIE implémentation [FirestoreSupportRepository] contre
/// fake_cloud_firestore.
///
/// [SupportControllerTest] (test/unit/support_controller_test.dart) mocke
/// entièrement [SupportRepository] — il ne vérifie donc jamais le payload
/// Firestore réellement construit par `submit()`. Ce fichier comble ce trou :
/// vérifie que les 8 champs attendus par les rules `support_requests`
/// (`firestore.rules`, bloc FEAT-025) sont bien tous présents, avec les
/// bons types et aucun champ en trop, et que `createdAt` est bien résolu en
/// timestamp serveur (pas une valeur cliente arbitraire).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyrent/features/support/data/support_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'lld-support-1';
const _email = 'bailleur@example.com';

void main() {
  group('FirestoreSupportRepository — payload conforme aux rules', () {
    test('submit() écrit exactement les 8 champs attendus par les rules, '
        'avec les bons types', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: _uid,
          email: _email,
          isAnonymous: false,
          isEmailVerified: true,
        ),
      );
      final repo = FirestoreSupportRepository(firestore, auth);

      await repo.submit(
        subject: 'Problème de quittance',
        message: 'La quittance de mars ne se génère pas.',
        appVersion: '1.0.0+42',
        appEnv: 'dev',
      );

      final snapshot = await firestore.collection('support_requests').get();
      expect(snapshot.docs, hasLength(1));
      final data = snapshot.docs.single.data();

      // Les 8 champs exacts des rules (`firestore.rules` — bloc
      // support_requests) : aucun champ en trop, aucun manquant.
      expect(data.keys.toSet(), {
        'landlordId',
        'email',
        'subject',
        'message',
        'appVersion',
        'appEnv',
        'status',
        'createdAt',
      });

      expect(data['landlordId'], _uid);
      expect(data['email'], _email);
      expect(data['subject'], 'Problème de quittance');
      expect(data['message'], 'La quittance de mars ne se génère pas.');
      expect(data['appVersion'], '1.0.0+42');
      expect(data['appEnv'], 'dev');
      expect(data['status'], 'new');
      // `createdAt == request.time` (rule) : résolu en Timestamp serveur,
      // pas laissé null ni en `FieldValue` non résolu.
      expect(data['createdAt'], isA<Timestamp>());
    });

    test('landlordId correspond toujours à auth.uid (jamais falsifiable côté '
        'client)', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'autre-uid', email: _email, isAnonymous: false),
      );
      final repo = FirestoreSupportRepository(firestore, auth);

      await repo.submit(
        subject: 'Sujet',
        message: 'Message',
        appVersion: '1.0.0+1',
        appEnv: 'prod',
      );

      final snapshot = await firestore.collection('support_requests').get();
      expect(snapshot.docs.single.data()['landlordId'], 'autre-uid');
    });

    test(
      'currentUser == null → StateError, aucune écriture Firestore',
      () async {
        final firestore = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(signedIn: false);
        final repo = FirestoreSupportRepository(firestore, auth);

        await expectLater(
          () => repo.submit(
            subject: 'Sujet',
            message: 'Message',
            appVersion: '1.0.0+1',
            appEnv: 'dev',
          ),
          throwsA(isA<StateError>()),
        );

        final snapshot = await firestore.collection('support_requests').get();
        expect(snapshot.docs, isEmpty);
      },
    );
  });
}
