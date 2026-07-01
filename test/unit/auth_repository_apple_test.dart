import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyrent/features/auth/data/apple_auth_exception.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
//
// `firebase_auth_mocks` (0.14.2) ne supporte pas `additionalUserInfo`
// (`MockUserCredential.additionalUserInfo` lève `UnimplementedError`), donc
// on injecte un `IsNewUserResolver` de test pour simuler isNewUser=true/false
// sans dépendre du SDK Firebase réel. Voir le commentaire dans
// `auth_repository.dart` (`IsNewUserResolver`) pour le contexte. Miroir
// strict de `auth_repository_google_test.dart`.
// ---------------------------------------------------------------------------

FirebaseAuthRepository _makeRepo({
  required bool isNewUser,
  MockFirebaseAuth? auth,
  FakeFirebaseFirestore? firestore,
}) {
  return FirebaseAuthRepository(
    auth ??
        MockFirebaseAuth(
          mockUser: MockUser(
            uid: 'uid-1',
            email: 'jean@exemple.fr',
            displayName: 'Jean Dupont',
          ),
        ),
    firestore ?? FakeFirebaseFirestore(),
    isNewUserResolver: (_) => isNewUser,
  );
}

void main() {
  group('FirebaseAuthRepository.signInWithApple', () {
    test(
      'isNewUser=true → delete() + signOut() + throw newUserOnLogin',
      () async {
        final mockUser = MockUser(
          uid: 'uid-new',
          email: 'new@exemple.fr',
          displayName: 'Nouveau',
        );
        final auth = MockFirebaseAuth(mockUser: mockUser);
        final firestore = FakeFirebaseFirestore();
        final repo = _makeRepo(
          isNewUser: true,
          auth: auth,
          firestore: firestore,
        );

        await expectLater(
          repo.signInWithApple(),
          throwsA(
            isA<FirebaseAuthException>().having(
              (e) => e.code,
              'code',
              AppleAuthErrorCode.newUserOnLogin,
            ),
          ),
        );

        // Le rollback signOut() doit avoir nettoyé la session courante.
        expect(auth.currentUser, isNull);
      },
    );

    test('isNewUser=false → pas de throw, succès silencieux', () async {
      final mockUser = MockUser(
        uid: 'uid-existing',
        email: 'existing@exemple.fr',
      );
      final auth = MockFirebaseAuth(mockUser: mockUser);
      final repo = _makeRepo(isNewUser: false, auth: auth);

      await expectLater(repo.signInWithApple(), completes);
    });
  });

  group('FirebaseAuthRepository.signUpWithApple', () {
    test('rgpdConsent=false → throw consentDeclined AVANT le popup', () async {
      final auth = MockFirebaseAuth();
      final repo = _makeRepo(isNewUser: true, auth: auth);

      await expectLater(
        repo.signUpWithApple(rgpdConsent: false),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            AppleAuthErrorCode.consentDeclined,
          ),
        ),
      );

      // Le popup n'a jamais été ouvert — aucun utilisateur courant.
      expect(auth.currentUser, isNull);
    });

    test(
      'rgpdConsent=true, isNewUser=true → doc landlords/{uid} avec signupProvider apple',
      () async {
        final mockUser = MockUser(
          uid: 'uid-apple-new',
          email: 'nouveau@exemple.fr',
          displayName: 'Nouveau Locataire',
        );
        final auth = MockFirebaseAuth(mockUser: mockUser);
        final firestore = FakeFirebaseFirestore();
        final repo = _makeRepo(
          isNewUser: true,
          auth: auth,
          firestore: firestore,
        );

        await repo.signUpWithApple(rgpdConsent: true);

        final doc = await firestore.doc('landlords/uid-apple-new').get();
        expect(doc.exists, isTrue);
        final data = doc.data()!;
        expect(data['signupProvider'], 'apple');
        expect(data['rgpdConsentSource'], 'apple-popup');
        expect(data['rgpdConsentVersion'], rgpdConsentVersion);
        expect(data['email'], 'nouveau@exemple.fr');
        expect(data['fullName'], 'Nouveau Locataire');
      },
    );

    test(
      'rgpdConsent=true, isNewUser=true + doc PRÉ-PROVISIONNÉ par CF → '
      'UPDATE qui ajoute signupProvider mais ne touche PAS rgpdConsentAt/Version',
      () async {
        final mockUser = MockUser(
          uid: 'uid-cf-provisioned-apple',
          email: 'cf@exemple.fr',
          displayName: 'CF Provisioned',
        );
        final auth = MockFirebaseAuth(mockUser: mockUser);
        final firestore = FakeFirebaseFirestore();

        // Simule la Cloud Function `beforeUserCreated` (handleNewUser) qui
        // provisionne le doc landlords/{uid} avec rgpdConsentAt avant que le
        // client n'ait la main. La rule Firestore UPDATE interdit ensuite
        // toute modification de rgpdConsentAt/Version — donc le repo doit
        // détecter ce cas et n'écrire QUE les métadonnées d'audit Apple.
        final originalConsentAt = Timestamp.fromDate(
          DateTime.utc(2026, 6, 30, 12, 0, 0),
        );
        await firestore.doc('landlords/uid-cf-provisioned-apple').set({
          'id': 'uid-cf-provisioned-apple',
          'email': 'cf@exemple.fr',
          'fullName': 'CF Provisioned',
          'phone': null,
          'address': null,
          'rgpdConsentAt': originalConsentAt,
          'rgpdConsentVersion': 'v1-2026-06',
          'createdAt': originalConsentAt,
          'updatedAt': originalConsentAt,
          'deletedAt': null,
        });

        final repo = _makeRepo(
          isNewUser: true,
          auth: auth,
          firestore: firestore,
        );

        await repo.signUpWithApple(rgpdConsent: true);

        final doc = await firestore
            .doc('landlords/uid-cf-provisioned-apple')
            .get();
        final data = doc.data()!;
        expect(data['signupProvider'], 'apple');
        expect(data['rgpdConsentSource'], 'apple-popup');
        // Les champs RGPD persistés par la CF ne sont PAS modifiés (la rule
        // UPDATE l'aurait sinon rejeté en prod).
        expect(data['rgpdConsentAt'], originalConsentAt);
        expect(data['rgpdConsentVersion'], 'v1-2026-06');
      },
    );

    test(
      'rgpdConsent=true, isNewUser=false → le doc landlord existant n\'est pas modifié',
      () async {
        final mockUser = MockUser(
          uid: 'uid-apple-existing',
          email: 'existant@exemple.fr',
          displayName: 'Compte Existant',
        );
        final auth = MockFirebaseAuth(mockUser: mockUser);
        final firestore = FakeFirebaseFirestore();
        // Doc pré-existant avec signupProvider='email' (compte créé via le
        // formulaire avant cette tentative de Apple sign-in).
        await firestore.doc('landlords/uid-apple-existing').set({
          'id': 'uid-apple-existing',
          'email': 'existant@exemple.fr',
          'fullName': 'Compte Existant',
          'signupProvider': 'email',
        });

        final repo = _makeRepo(
          isNewUser: false,
          auth: auth,
          firestore: firestore,
        );

        await repo.signUpWithApple(rgpdConsent: true);

        final doc = await firestore.doc('landlords/uid-apple-existing').get();
        final data = doc.data()!;
        // signupProvider reste 'email' — jamais surchargé par le flow Apple.
        expect(data['signupProvider'], 'email');
      },
    );

    test(
      'displayName null (re-signup post-rollback) → fallback sur email',
      () async {
        // Spécificité Apple documentée dans auth_repository.dart : après un
        // rollback delete() + un nouveau signUpWithApple depuis le même
        // Apple ID, `user.displayName` peut être `null` car Apple ne
        // renvoie le nom qu'à la toute première autorisation OAuth.
        final mockUser = MockUser(
          uid: 'uid-apple-no-name',
          email: 'sansnom@exemple.fr',
        );
        final auth = MockFirebaseAuth(mockUser: mockUser);
        final firestore = FakeFirebaseFirestore();
        final repo = _makeRepo(
          isNewUser: true,
          auth: auth,
          firestore: firestore,
        );

        await repo.signUpWithApple(rgpdConsent: true);

        final doc = await firestore.doc('landlords/uid-apple-no-name').get();
        final data = doc.data()!;
        expect(data['fullName'], 'sansnom@exemple.fr');
      },
    );
  });
}
