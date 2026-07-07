import 'package:easyrent/features/auth/application/login_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/auth_cta_label.dart';
import 'package:easyrent/features/auth/domain/auth_error.dart';
import 'package:easyrent/features/auth/domain/login_page_state.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  bool signInCalled = false;
  bool signOutCalled = false;
  bool signInWithGoogleCalled = false;
  bool signInWithAppleCalled = false;
  String? lastEmail;
  Exception? signInError;
  Exception? signInWithGoogleError;
  Exception? signInWithAppleError;

  @override
  Stream<User?> get authStateChanges => const Stream<User?>.empty();

  @override
  User? get currentUser => null;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalled = true;
    lastEmail = email;
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {}

  @override
  Future<void> signInWithGoogle() async {
    signInWithGoogleCalled = true;
    if (signInWithGoogleError != null) throw signInWithGoogleError!;
  }

  @override
  Future<void> signUpWithGoogle({required bool rgpdConsent}) async {}

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
  Future<void> sendCurrentUserEmailVerification() async {}

  @override
  Future<void> signInWithApple() async {
    signInWithAppleCalled = true;
    if (signInWithAppleError != null) throw signInWithAppleError!;
  }

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
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  Future<void> reauthenticateWithPassword(String currentPassword) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}
}

class _ThrowingSignOutRepo extends _FakeAuthRepository {
  @override
  Future<void> signOut() async => throw Exception('signOut failed');
}

/// Fake pour l'edge case FEAT-021 : signInWithPassword réussit MAIS
/// l'utilisateur n'a pas vérifié son email. Le controller doit détecter ce
/// cas, relancer un email de vérif, signer out, et afficher un message
/// explicite. MockUser de firebase_auth_mocks permet de contrôler
/// `emailVerified` (via `isEmailVerified: false`).
class _UnverifiedUserRepo extends _FakeAuthRepository {
  _UnverifiedUserRepo()
    : _mockUser = MockUser(
        uid: 'uid-unverified',
        email: 'user@exemple.fr',
        isEmailVerified: false,
      );

  final MockUser _mockUser;
  bool sendVerificationCalled = false;

  @override
  User? get currentUser => _mockUser;

  @override
  Future<void> sendCurrentUserEmailVerification() async {
    sendVerificationCalled = true;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

LoginController _makeController(_FakeAuthRepository repo) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  return container.read(loginControllerProvider.notifier);
}

bool _isError(LoginPageState s) =>
    s.maybeWhen(error: (m, c, l) => true, orElse: () => false);

String _errorMsg(LoginPageState s) =>
    s.maybeWhen(error: (m, c, l) => m, orElse: () => '');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LoginController', () {
    test('état initial est idle', () {
      final ctrl = _makeController(_FakeAuthRepository());
      expect(ctrl.state, const LoginPageState.idle());
    });

    group('signIn — chemin nominal', () {
      test('transitions idle → submitting → idle après succès', () async {
        final repo = _FakeAuthRepository();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final states = <LoginPageState>[];
        container.listen<LoginPageState>(
          loginControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        await container
            .read(loginControllerProvider.notifier)
            .signIn(email: 'user@exemple.fr', password: 'Password1');

        expect(states[0], const LoginPageState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
        );
        expect(states[2], const LoginPageState.idle());
        expect(repo.signInCalled, isTrue);
        expect(repo.lastEmail, 'user@exemple.fr');
      });

      test("trimme l'email avant de l'envoyer au repo", () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: '  user@exemple.fr  ', password: 'Password1');
        expect(repo.lastEmail, 'user@exemple.fr');
      });
    });

    group('signIn — validation', () {
      test('email invalide → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: 'bademail', password: 'Password1');
        expect(repo.signInCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), AuthError.invalidEmailFormat.name);
      });

      test('mot de passe vide → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: 'user@exemple.fr', password: '');
        expect(repo.signInCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), AuthError.passwordRequired.name);
      });
    });

    group('signIn — erreurs Firebase', () {
      test('invalid_credentials → AuthError.invalidCredentials', () async {
        final repo = _FakeAuthRepository()
          ..signInError = FirebaseAuthException(
            code: 'invalid-credential',
            message: 'Invalid login credentials',
          );
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: 'user@exemple.fr', password: 'Password1');
        expect(_errorMsg(ctrl.state), AuthError.invalidCredentials.name);
      });

      test('email_not_confirmed → AuthError.invalidCredentials', () async {
        final repo = _FakeAuthRepository()
          ..signInError = FirebaseAuthException(
            code: 'invalid-credential',
            message: 'Email not confirmed',
          );
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: 'user@exemple.fr', password: 'Password1');
        expect(_errorMsg(ctrl.state), AuthError.invalidCredentials.name);
      });

      test('exception inconnue → AuthError.unknown', () async {
        final repo = _FakeAuthRepository()
          ..signInError = Exception('network error');
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: 'user@exemple.fr', password: 'Password1');
        expect(_errorMsg(ctrl.state), AuthError.unknown.name);
      });
    });

    group('signIn — email non vérifié (FEAT-021)', () {
      test(
        'signIn réussi mais emailVerified=false → resend + signOut + message',
        () async {
          final repo = _UnverifiedUserRepo();
          final ctrl = _makeController(repo);

          await ctrl.signIn(email: 'user@exemple.fr', password: 'Password1');

          expect(repo.signInCalled, isTrue);
          // Le controller a détecté emailVerified=false et déclenché la
          // procédure de relance automatique.
          expect(repo.sendVerificationCalled, isTrue);
          expect(repo.signOutCalled, isTrue);
          expect(_isError(ctrl.state), isTrue);
          expect(_errorMsg(ctrl.state), AuthError.emailNotVerified.name);
        },
      );
    });

    group('signInWithGoogle', () {
      test('happy path → submitting puis idle, repo appelé', () async {
        final repo = _FakeAuthRepository();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final states = <LoginPageState>[];
        container.listen<LoginPageState>(
          loginControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        await container
            .read(loginControllerProvider.notifier)
            .signInWithGoogle();

        expect(repo.signInWithGoogleCalled, isTrue);
        expect(states.first, const LoginPageState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
        );
        expect(states.last, const LoginPageState.idle());
      });

      test(
        'newUserOnLogin → état error avec CTA /signup et label "Créer un compte"',
        () async {
          final repo = _FakeAuthRepository()
            ..signInWithGoogleError = FirebaseAuthException(
              code: 'baillan/google-new-user-on-login',
              message: 'no associated landlord',
            );
          final ctrl = _makeController(repo);
          await ctrl.signInWithGoogle();

          final state = ctrl.state;
          expect(_isError(state), isTrue);
          final cta = state.maybeWhen(
            error: (m, ctaRoute, ctaLabel) => (ctaRoute, ctaLabel),
            orElse: () => (null, null),
          );
          expect(cta.$1, '/signup');
          expect(cta.$2, AuthCtaLabel.createAccount.name);
          expect(_errorMsg(state), AuthError.googleNewUserOnLogin.name);
        },
      );

      test(
        'account-exists-with-different-credential → error SANS CTA (pas un cas /login)',
        () async {
          final repo = _FakeAuthRepository()
            ..signInWithGoogleError = FirebaseAuthException(
              code: 'account-exists-with-different-credential',
              message: 'conflict',
            );
          final ctrl = _makeController(repo);
          await ctrl.signInWithGoogle();

          final cta = ctrl.state.maybeWhen(
            error: (m, ctaRoute, ctaLabel) => (ctaRoute, ctaLabel),
            orElse: () => ('NOT_ERROR', 'NOT_ERROR'),
          );
          // Pas de CTA spécifique sur /login pour ce code — l'utilisateur
          // doit utiliser son mot de passe email/password.
          expect(cta.$1, isNull);
          expect(cta.$2, isNull);
        },
      );

      test('exception générique → AuthError.unknown', () async {
        final repo = _FakeAuthRepository()
          ..signInWithGoogleError = Exception('boom');
        final ctrl = _makeController(repo);
        await ctrl.signInWithGoogle();
        expect(_errorMsg(ctrl.state), AuthError.unknown.name);
      });
    });

    group('signInWithApple', () {
      test('happy path → submitting puis idle, repo appelé', () async {
        final repo = _FakeAuthRepository();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final states = <LoginPageState>[];
        container.listen<LoginPageState>(
          loginControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        await container
            .read(loginControllerProvider.notifier)
            .signInWithApple();

        expect(repo.signInWithAppleCalled, isTrue);
        expect(states.first, const LoginPageState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
        );
        expect(states.last, const LoginPageState.idle());
      });

      test(
        'newUserOnLogin → état error avec CTA /signup et label "Créer un compte"',
        () async {
          final repo = _FakeAuthRepository()
            ..signInWithAppleError = FirebaseAuthException(
              code: 'baillan/apple-new-user-on-login',
              message: 'no associated landlord',
            );
          final ctrl = _makeController(repo);
          await ctrl.signInWithApple();

          final state = ctrl.state;
          expect(_isError(state), isTrue);
          final cta = state.maybeWhen(
            error: (m, ctaRoute, ctaLabel) => (ctaRoute, ctaLabel),
            orElse: () => (null, null),
          );
          expect(cta.$1, '/signup');
          expect(cta.$2, AuthCtaLabel.createAccount.name);
          expect(_errorMsg(state), AuthError.appleNewUserOnLogin.name);
        },
      );

      test(
        'account-exists-with-different-credential → error SANS CTA (pas un cas /login)',
        () async {
          final repo = _FakeAuthRepository()
            ..signInWithAppleError = FirebaseAuthException(
              code: 'account-exists-with-different-credential',
              message: 'conflict',
            );
          final ctrl = _makeController(repo);
          await ctrl.signInWithApple();

          final cta = ctrl.state.maybeWhen(
            error: (m, ctaRoute, ctaLabel) => (ctaRoute, ctaLabel),
            orElse: () => ('NOT_ERROR', 'NOT_ERROR'),
          );
          expect(cta.$1, isNull);
          expect(cta.$2, isNull);
        },
      );

      test('exception générique → AuthError.unknown', () async {
        final repo = _FakeAuthRepository()
          ..signInWithAppleError = Exception('boom');
        final ctrl = _makeController(repo);
        await ctrl.signInWithApple();
        expect(_errorMsg(ctrl.state), AuthError.unknown.name);
      });
    });

    group('signOut', () {
      test('appelle signOut repo et repasse à idle', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signOut();
        expect(repo.signOutCalled, isTrue);
        expect(ctrl.state, const LoginPageState.idle());
      });

      test('reste à idle même si repo lève exception (finally)', () async {
        final repo = _ThrowingSignOutRepo();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);
        final ctrl = container.read(loginControllerProvider.notifier);
        await ctrl.signOut();
        expect(ctrl.state, const LoginPageState.idle());
      });
    });
  });
}
