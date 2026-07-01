import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faux repository dont on contrôle intégralement le flux `authStateChanges`
/// et le `currentUser` en cache — permet de tester chaque branche de
/// [sessionStateProvider] sans dépendre de Firebase réel.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._user);

  final User? _user;

  @override
  Stream<User?> get authStateChanges => Stream.value(_user);

  @override
  User? get currentUser => _user;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {}

  @override
  Future<void> sendCurrentUserEmailVerification() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signUpWithGoogle({required bool rgpdConsent}) async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signUpWithApple({required bool rgpdConsent}) async {}

  @override
  Future<void> signInAnonymously() async {}

  @override
  Future<void> linkAnonymousWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
    required bool rgpdConsent,
  }) async {}

  @override
  Future<void> linkAnonymousWithGoogle({required bool rgpdConsent}) async {}

  @override
  Future<void> linkAnonymousWithApple({required bool rgpdConsent}) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<String> verifyPasswordResetCode(String code) async =>
      'test@example.com';

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<void> signOut() async {}
}

SessionState _read(User? user) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository(user)),
    ],
  );
  addTearDown(container.dispose);
  // Force la résolution synchrone du StreamProvider (Stream.value émet dans
  // un microtask ; container.read seul verrait `loading` sinon). On lit
  // sessionStateProvider après un pump manuel du event loop.
  return container.read(sessionStateProvider);
}

void main() {
  group('sessionStateProvider — dérivation depuis User?', () {
    test('user null → unauthenticated', () {
      expect(_read(null), SessionState.unauthenticated);
    });

    test('user anonyme (isAnonymous=true) → anonymous', () {
      final user = MockUser(isAnonymous: true, uid: 'anon-1');
      expect(_read(user), SessionState.anonymous);
    });

    test('user non-anonyme + emailVerified=true → fullyAuthenticated', () {
      final user = MockUser(
        isAnonymous: false,
        isEmailVerified: true,
        uid: 'uid-1',
      );
      expect(_read(user), SessionState.fullyAuthenticated);
    });

    test('user non-anonyme + emailVerified=false → unauthenticated '
        '(compte créé mais email pas encore vérifié, FEAT-021)', () {
      final user = MockUser(
        isAnonymous: false,
        isEmailVerified: false,
        uid: 'uid-2',
      );
      expect(_read(user), SessionState.unauthenticated);
    });

    test('user anonyme reste anonymous même si emailVerified=false '
        '(emailVerified non pertinent pour un compte anonyme)', () {
      final user = MockUser(
        isAnonymous: true,
        isEmailVerified: false,
        uid: 'anon-2',
      );
      expect(_read(user), SessionState.anonymous);
    });
  });

  group('isAuthenticatedProvider — shim rétrocompatible', () {
    test('true seulement si fullyAuthenticated', () {
      final verifiedUser = MockUser(isAnonymous: false, isEmailVerified: true);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(verifiedUser),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(isAuthenticatedProvider), isTrue);
    });

    test('false pour anonyme', () {
      final anonUser = MockUser(isAnonymous: true);
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(anonUser),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(isAuthenticatedProvider), isFalse);
    });

    test('false pour null', () {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository(null)),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(isAuthenticatedProvider), isFalse);
    });
  });
}
