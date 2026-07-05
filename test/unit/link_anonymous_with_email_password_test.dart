import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/data/google_auth_exception.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
//
// `firebase_auth_mocks` (0.14.2) a un bug connu : `MockUser.linkWithCredential`
// construit un `MockUserCredential(false, mockUser: this)` alors que
// `this.isAnonymous` reste `true` (champ final) → l'assertion interne du
// package échoue systématiquement en debug. On injecte donc un
// [LinkWithCredentialFn] de test qui simule le comportement réel
// (upgrade : même UID, isAnonymous devient false) sans dépendre du SDK.
// ---------------------------------------------------------------------------

class _FakeLinkedCredential implements UserCredential {
  _FakeLinkedCredential(this.user);

  @override
  final User? user;

  @override
  AdditionalUserInfo? get additionalUserInfo => null;

  @override
  AuthCredential? get credential => null;
}

void main() {
  group('FirebaseAuthRepository.linkAnonymousWithEmailPassword', () {
    test(
      'rgpdConsent=false → throw consentDeclined AVANT tout appel',
      () async {
        final anonUser = MockUser(isAnonymous: true, uid: 'anon-1');
        final auth = MockFirebaseAuth(mockUser: anonUser, signedIn: true);
        var linkCalled = false;
        var finalizeCalled = false;

        final repo = FirebaseAuthRepository(
          auth,
          FakeFirebaseFirestore(),
          linkWithCredential: (user, credential) async {
            linkCalled = true;
            return _FakeLinkedCredential(user);
          },
          finalizeUpgrade:
              ({required rgpdConsent, required rgpdConsentVersion}) async {
                finalizeCalled = true;
              },
        );

        await expectLater(
          repo.linkAnonymousWithEmailPassword(
            email: 'jean@exemple.fr',
            password: 'motdepasse1',
            fullName: 'Jean Dupont',
            rgpdConsent: false,
          ),
          throwsA(
            isA<FirebaseAuthException>().having(
              (e) => e.code,
              'code',
              GoogleAuthErrorCode.consentDeclined,
            ),
          ),
        );

        expect(linkCalled, isFalse);
        expect(finalizeCalled, isFalse);
      },
    );

    test(
      'currentUser non-anonyme → throw StateError avant tout appel',
      () async {
        final nonAnonUser = MockUser(isAnonymous: false, uid: 'uid-1');
        final auth = MockFirebaseAuth(mockUser: nonAnonUser, signedIn: true);
        var linkCalled = false;

        final repo = FirebaseAuthRepository(
          auth,
          FakeFirebaseFirestore(),
          linkWithCredential: (user, credential) async {
            linkCalled = true;
            return _FakeLinkedCredential(user);
          },
        );

        await expectLater(
          repo.linkAnonymousWithEmailPassword(
            email: 'jean@exemple.fr',
            password: 'motdepasse1',
            fullName: 'Jean Dupont',
            rgpdConsent: true,
          ),
          throwsA(isA<StateError>()),
        );
        expect(linkCalled, isFalse);
      },
    );

    test('currentUser null → throw StateError avant tout appel', () async {
      final auth = MockFirebaseAuth();
      final repo = FirebaseAuthRepository(auth, FakeFirebaseFirestore());

      await expectLater(
        repo.linkAnonymousWithEmailPassword(
          email: 'jean@exemple.fr',
          password: 'motdepasse1',
          fullName: 'Jean Dupont',
          rgpdConsent: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('succès : link + updateDisplayName + finalize callable + verification '
        'email + signOut, UID préservé', () async {
      final anonUser = MockUser(isAnonymous: true, uid: 'anon-preserved-uid');
      final auth = MockFirebaseAuth(mockUser: anonUser, signedIn: true);

      String? linkedEmail;
      String? linkedPassword;
      User? linkedUser;
      bool? finalizeRgpdConsent;
      String? finalizeVersion;

      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        linkWithCredential: (user, credential) async {
          linkedUser = user;
          if (credential is EmailAuthCredential) {
            linkedEmail = credential.email;
            linkedPassword = credential.password;
          }
          // Simule l'upgrade : même UID, isAnonymous devient false.
          final upgraded = MockUser(
            isAnonymous: false,
            uid: user.uid,
            email: linkedEmail,
          );
          return _FakeLinkedCredential(upgraded);
        },
        finalizeUpgrade:
            ({required rgpdConsent, required rgpdConsentVersion}) async {
              finalizeRgpdConsent = rgpdConsent;
              finalizeVersion = rgpdConsentVersion;
            },
      );

      await repo.linkAnonymousWithEmailPassword(
        email: 'jean@exemple.fr',
        password: 'motdepasse1',
        fullName: 'Jean Dupont',
        rgpdConsent: true,
      );

      expect(linkedUser?.uid, 'anon-preserved-uid');
      expect(linkedEmail, 'jean@exemple.fr');
      expect(linkedPassword, 'motdepasse1');
      expect(finalizeRgpdConsent, isTrue);
      expect(finalizeVersion, rgpdConsentVersion);
      // signOut() final — plus de session active.
      expect(auth.currentUser, isNull);
    });

    test('finalize callable échoue → exception propagée, PAS de signOut '
        '(le lien Auth est déjà fait, on ne veut pas perdre la session '
        'permettant un retry)', () async {
      final anonUser = MockUser(isAnonymous: true, uid: 'anon-retry');
      final auth = MockFirebaseAuth(mockUser: anonUser, signedIn: true);

      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        linkWithCredential: (user, credential) async {
          final upgraded = MockUser(isAnonymous: false, uid: user.uid);
          return _FakeLinkedCredential(upgraded);
        },
        finalizeUpgrade:
            ({required rgpdConsent, required rgpdConsentVersion}) async {
              throw Exception('backend unavailable');
            },
      );

      await expectLater(
        repo.linkAnonymousWithEmailPassword(
          email: 'jean@exemple.fr',
          password: 'motdepasse1',
          fullName: 'Jean Dupont',
          rgpdConsent: true,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('FirebaseAuthRepository.linkAnonymousWithGoogle', () {
    test('rgpdConsent=false → throw consentDeclined AVANT le popup', () async {
      final anonUser = MockUser(isAnonymous: true, uid: 'anon-2');
      final auth = MockFirebaseAuth(mockUser: anonUser, signedIn: true);
      var popupCalled = false;

      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        linkWithPopup: (user, provider) async {
          popupCalled = true;
          return _FakeLinkedCredential(user);
        },
      );

      await expectLater(
        repo.linkAnonymousWithGoogle(rgpdConsent: false),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            GoogleAuthErrorCode.consentDeclined,
          ),
        ),
      );
      expect(popupCalled, isFalse);
    });

    test('succès : linkWithPopup + finalize callable appelés', () async {
      final anonUser = MockUser(isAnonymous: true, uid: 'anon-google-uid');
      final auth = MockFirebaseAuth(mockUser: anonUser, signedIn: true);
      AuthProvider? capturedProvider;
      bool? finalizeCalled;

      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        linkWithPopup: (user, provider) async {
          capturedProvider = provider;
          final upgraded = MockUser(isAnonymous: false, uid: user.uid);
          return _FakeLinkedCredential(upgraded);
        },
        finalizeUpgrade:
            ({required rgpdConsent, required rgpdConsentVersion}) async {
              finalizeCalled = rgpdConsent;
            },
      );

      await repo.linkAnonymousWithGoogle(rgpdConsent: true);

      expect(capturedProvider, isA<GoogleAuthProvider>());
      expect(finalizeCalled, isTrue);
    });

    test('currentUser non-anonyme → throw StateError', () async {
      final nonAnonUser = MockUser(isAnonymous: false, uid: 'uid-2');
      final auth = MockFirebaseAuth(mockUser: nonAnonUser, signedIn: true);
      final repo = FirebaseAuthRepository(auth, FakeFirebaseFirestore());

      await expectLater(
        repo.linkAnonymousWithGoogle(rgpdConsent: true),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FirebaseAuthRepository.linkAnonymousWithApple', () {
    test('rgpdConsent=false → throw consentDeclined AVANT le popup', () async {
      final anonUser = MockUser(isAnonymous: true, uid: 'anon-3');
      final auth = MockFirebaseAuth(mockUser: anonUser, signedIn: true);
      var popupCalled = false;

      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        linkWithPopup: (user, provider) async {
          popupCalled = true;
          return _FakeLinkedCredential(user);
        },
      );

      await expectLater(
        repo.linkAnonymousWithApple(rgpdConsent: false),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(popupCalled, isFalse);
    });

    test('succès : linkWithPopup (apple.com) + finalize callable', () async {
      final anonUser = MockUser(isAnonymous: true, uid: 'anon-apple-uid');
      final auth = MockFirebaseAuth(mockUser: anonUser, signedIn: true);
      AuthProvider? capturedProvider;
      bool? finalizeCalled;

      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        linkWithPopup: (user, provider) async {
          capturedProvider = provider;
          final upgraded = MockUser(isAnonymous: false, uid: user.uid);
          return _FakeLinkedCredential(upgraded);
        },
        finalizeUpgrade:
            ({required rgpdConsent, required rgpdConsentVersion}) async {
              finalizeCalled = rgpdConsent;
            },
      );

      await repo.linkAnonymousWithApple(rgpdConsent: true);

      expect(capturedProvider, isA<OAuthProvider>());
      expect((capturedProvider as OAuthProvider).providerId, 'apple.com');
      expect(finalizeCalled, isTrue);
    });
  });

  group('FirebaseAuthRepository.signInAnonymously', () {
    test('délègue à FirebaseAuth.signInAnonymously()', () async {
      final auth = MockFirebaseAuth();
      final repo = FirebaseAuthRepository(auth, FakeFirebaseFirestore());

      await repo.signInAnonymously();

      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.isAnonymous, isTrue);
    });
  });
}
