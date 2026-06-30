import 'package:easyrent/features/auth/application/forgot_password_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/forgot_password_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  bool sendResetCalled = false;
  String? lastEmail;
  Exception? sendError;

  @override
  Stream<User?> get authStateChanges => const Stream<User?>.empty();

  @override
  User? get currentUser => null;

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
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signUpWithGoogle({required bool rgpdConsent}) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    sendResetCalled = true;
    lastEmail = email;
    if (sendError != null) throw sendError!;
  }

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ForgotPasswordController _makeController(_FakeAuthRepository repo) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  return container.read(forgotPasswordControllerProvider.notifier);
}

bool _isError(ForgotPasswordState s) =>
    s.maybeWhen(error: (_) => true, orElse: () => false);

bool _isEmailSent(ForgotPasswordState s) =>
    s.maybeWhen(emailSent: () => true, orElse: () => false);

String _errorMsg(ForgotPasswordState s) =>
    s.maybeWhen(error: (m) => m, orElse: () => '');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ForgotPasswordController', () {
    test('état initial est idle', () {
      final ctrl = _makeController(_FakeAuthRepository());
      expect(ctrl.state, const ForgotPasswordState.idle());
    });

    group('sendResetEmail — chemin nominal', () {
      test('transitions idle → submitting → emailSent', () async {
        final repo = _FakeAuthRepository();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final states = <ForgotPasswordState>[];
        container.listen<ForgotPasswordState>(
          forgotPasswordControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        await container
            .read(forgotPasswordControllerProvider.notifier)
            .sendResetEmail('user@exemple.fr');

        expect(states[0], const ForgotPasswordState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
        );
        expect(_isEmailSent(states[2]), isTrue);
        expect(repo.sendResetCalled, isTrue);
        expect(repo.lastEmail, 'user@exemple.fr');
      });

      test("trimme l'email", () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.sendResetEmail('  user@exemple.fr  ');
        expect(repo.lastEmail, 'user@exemple.fr');
      });
    });

    group('sendResetEmail — validation', () {
      test('email invalide → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.sendResetEmail('bademail');
        expect(repo.sendResetCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), 'Adresse email invalide');
      });

      test('email vide → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.sendResetEmail('');
        expect(repo.sendResetCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
      });
    });

    group('sendResetEmail — erreurs Firebase (OWASP anti-énumération)', () {
      test(
        'rate limit → état error (exception au comportement anti-énumération)',
        () async {
          final repo = _FakeAuthRepository()
            ..sendError = FirebaseAuthException(
              code: 'too-many-requests',
              message: 'Email rate limit exceeded',
            );
          final ctrl = _makeController(repo);
          await ctrl.sendResetEmail('user@exemple.fr');
          expect(_isError(ctrl.state), isTrue);
          expect(_errorMsg(ctrl.state), contains('Trop de demandes'));
        },
      );

      test(
        'user_not_found → emailSent quand même (OWASP: pas de fuite compte)',
        () async {
          final repo = _FakeAuthRepository()
            ..sendError = FirebaseAuthException(
              code: 'user_not_found',
              message: 'User not found',
            );
          final ctrl = _makeController(repo);
          await ctrl.sendResetEmail('user@exemple.fr');
          // OWASP: l'état doit être emailSent même si le compte n'existe pas.
          expect(_isEmailSent(ctrl.state), isTrue);
        },
      );

      test(
        'AuthException inconnue → emailSent (OWASP: anti-énumération)',
        () async {
          final repo = _FakeAuthRepository()
            ..sendError = FirebaseAuthException(
              code: 'unknown',
              message: 'some supabase error',
            );
          final ctrl = _makeController(repo);
          await ctrl.sendResetEmail('user@exemple.fr');
          expect(_isEmailSent(ctrl.state), isTrue);
        },
      );

      test('exception réseau → emailSent (OWASP: anti-énumération)', () async {
        final repo = _FakeAuthRepository()
          ..sendError = Exception('network error');
        final ctrl = _makeController(repo);
        await ctrl.sendResetEmail('user@exemple.fr');
        expect(_isEmailSent(ctrl.state), isTrue);
      });

      test('email invalide → error (validation locale, pas OWASP)', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.sendResetEmail('bademail');
        // La validation locale n'est pas concernée par l'anti-énumération.
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), 'Adresse email invalide');
      });
    });
  });
}
