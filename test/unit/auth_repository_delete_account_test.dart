import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// FEAT-045 — suppression de compte : reauth OAuth, révocation Apple,
// deleteAccount (callable + signOut local).
//
// Les flux OAuth de réauthentification et la callable sont injectés
// (`ReauthenticateWithProviderFn`, `DeleteAccountCallableFn`,
// `RevokeAppleTokenFn`) : `firebase_auth_mocks` (0.14.2) ne surcharge ni
// `reauthenticateWithPopup/Provider` ni `revokeTokenWithAuthorizationCode`,
// et `additionalUserInfo` lève `UnimplementedError` — voir les typedefs de
// `auth_repository.dart`.
// ---------------------------------------------------------------------------

MockUser _makeUser({bool isAnonymous = false}) => MockUser(
  uid: 'uid-1',
  email: isAnonymous ? null : 'jean@exemple.fr',
  isAnonymous: isAnonymous,
);

MockFirebaseAuth _signedInAuth(MockUser user) =>
    MockFirebaseAuth(signedIn: true, mockUser: user);

/// [UserCredential] minimal pour le retour du flux de reauth injecté.
///
/// `firebase_auth_mocks` n'exporte pas `MockUserCredential`, et le
/// repository ne touche jamais au credential lui-même (il le passe au
/// résolveur `appleAuthorizationCode`, injecté dans ces tests) — un fake
/// noSuchMethod suffit.
class _FakeUserCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('FirebaseAuthRepository.reauthenticateWithOAuthProvider', () {
    test('délègue au flux injecté et retourne le code Apple résolu', () async {
      final mockUser = _makeUser();
      final auth = _signedInAuth(mockUser);
      AuthProvider? capturedProvider;
      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        reauthenticateWithProvider: (user, provider) async {
          capturedProvider = provider;
          return _FakeUserCredential();
        },
        appleAuthorizationCode: (_) => 'apple-code-123',
      );

      final code = await repo.reauthenticateWithOAuthProvider('apple.com');

      expect(code, 'apple-code-123');
      expect(capturedProvider, isA<OAuthProvider>());
      expect((capturedProvider as OAuthProvider).providerId, 'apple.com');
    });

    test('Google : jamais de authorizationCode (retourne null)', () async {
      final mockUser = _makeUser();
      final auth = _signedInAuth(mockUser);
      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        reauthenticateWithProvider: (user, provider) async =>
            _FakeUserCredential(),
        // Résolveur volontairement non-null : il ne doit PAS être consulté
        // pour Google.
        appleAuthorizationCode: (_) => 'should-not-be-used',
      );

      final code = await repo.reauthenticateWithOAuthProvider('google.com');

      expect(code, isNull);
    });

    test('provider inconnu → ArgumentError', () async {
      final repo = FirebaseAuthRepository(
        _signedInAuth(_makeUser()),
        FakeFirebaseFirestore(),
      );

      await expectLater(
        repo.reauthenticateWithOAuthProvider('github.com'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('aucun utilisateur signé → StateError', () async {
      final repo = FirebaseAuthRepository(
        MockFirebaseAuth(),
        FakeFirebaseFirestore(),
      );

      await expectLater(
        repo.reauthenticateWithOAuthProvider('google.com'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FirebaseAuthRepository.revokeAppleToken', () {
    test('délègue au revoke injecté avec le code', () async {
      String? revokedCode;
      final repo = FirebaseAuthRepository(
        _signedInAuth(_makeUser()),
        FakeFirebaseFirestore(),
        revokeAppleTokenFn: (code) async => revokedCode = code,
      );

      await repo.revokeAppleToken('code-xyz');

      expect(revokedCode, 'code-xyz');
    });

    test('best-effort : un échec de révocation ne remonte JAMAIS', () async {
      final repo = FirebaseAuthRepository(
        _signedInAuth(_makeUser()),
        FakeFirebaseFirestore(),
        revokeAppleTokenFn: (_) async =>
            throw FirebaseAuthException(code: 'internal-error'),
      );

      await expectLater(repo.revokeAppleToken('code-xyz'), completes);
    });
  });

  group('FirebaseAuthRepository.deleteAccount', () {
    test('appelle la callable PUIS signe out localement', () async {
      final auth = _signedInAuth(_makeUser());
      var callableCalled = false;
      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        deleteAccountCallable: () async {
          callableCalled = true;
          // La session doit encore être active au moment de la purge
          // (la callable exige un token authentifié).
          expect(auth.currentUser, isNotNull);
        },
      );

      await repo.deleteAccount();

      expect(callableCalled, isTrue);
      expect(auth.currentUser, isNull);
    });

    test(
      'un échec de la callable remonte SANS signOut (retry possible)',
      () async {
        final auth = _signedInAuth(_makeUser());
        final repo = FirebaseAuthRepository(
          auth,
          FakeFirebaseFirestore(),
          deleteAccountCallable: () async =>
              throw Exception('backend unavailable'),
        );

        await expectLater(repo.deleteAccount(), throwsA(isA<Exception>()));
        // Session préservée : l'utilisateur peut relancer la suppression.
        expect(auth.currentUser, isNotNull);
      },
    );

    test('fonctionne pour une session anonyme', () async {
      final auth = _signedInAuth(_makeUser(isAnonymous: true));
      var callableCalled = false;
      final repo = FirebaseAuthRepository(
        auth,
        FakeFirebaseFirestore(),
        deleteAccountCallable: () async => callableCalled = true,
      );

      await repo.deleteAccount();

      expect(callableCalled, isTrue);
      expect(auth.currentUser, isNull);
    });
  });
}
