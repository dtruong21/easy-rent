import 'package:easyrent/features/auth/application/change_password_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/change_password_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository (Firebase)
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async =>
      null;

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {}

  @override
  Future<void> deleteAccount() async {}

  bool reauthenticateCalled = false;
  bool updatePasswordCalled = false;
  String? lastCurrentPassword;
  String? lastNewPassword;
  Exception? reauthenticateError;
  Exception? updatePasswordError;

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
  Future<void> reauthenticateWithPassword(String currentPassword) async {
    reauthenticateCalled = true;
    lastCurrentPassword = currentPassword;
    final err = reauthenticateError;
    if (err != null) throw err;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    updatePasswordCalled = true;
    lastNewPassword = newPassword;
    final err = updatePasswordError;
    if (err != null) throw err;
  }

  @override
  Future<void> signOut() async {}
}

ChangePasswordController _makeController(_FakeAuthRepository repo) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  return container.read(changePasswordControllerProvider.notifier);
}

bool _isError(ChangePasswordState s) =>
    s.maybeWhen(error: (_) => true, orElse: () => false);

bool _isSuccess(ChangePasswordState s) =>
    s.maybeWhen(success: () => true, orElse: () => false);

String _errorMsg(ChangePasswordState s) =>
    s.maybeWhen(error: (m) => m, orElse: () => '');

void main() {
  group('ChangePasswordController', () {
    test('état initial est idle', () {
      final ctrl = _makeController(_FakeAuthRepository());
      expect(ctrl.state, const ChangePasswordState.idle());
    });

    group('submit — chemin nominal', () {
      test('transitions idle → submitting → success', () async {
        final repo = _FakeAuthRepository();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final states = <ChangePasswordState>[];
        container.listen<ChangePasswordState>(
          changePasswordControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        await container
            .read(changePasswordControllerProvider.notifier)
            .submit(
              currentPassword: 'OldPassword1',
              newPassword: 'NewPassword2',
              confirmPassword: 'NewPassword2',
            );

        expect(states[0], const ChangePasswordState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
        );
        expect(_isSuccess(states[2]), isTrue);
        expect(repo.reauthenticateCalled, isTrue);
        expect(repo.lastCurrentPassword, 'OldPassword1');
        expect(repo.updatePasswordCalled, isTrue);
        expect(repo.lastNewPassword, 'NewPassword2');
      });
    });

    group('submit — validation locale', () {
      test('nouveau mot de passe trop court → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          currentPassword: 'OldPassword1',
          newPassword: 'abc',
          confirmPassword: 'abc',
        );
        expect(repo.reauthenticateCalled, isFalse);
        expect(repo.updatePasswordCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), '8 caractères minimum');
      });

      test('nouveau mot de passe sans chiffre → error', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          currentPassword: 'OldPassword1',
          newPassword: 'abcdefgh',
          confirmPassword: 'abcdefgh',
        );
        expect(repo.reauthenticateCalled, isFalse);
        expect(_errorMsg(ctrl.state), 'Au moins un chiffre');
      });

      test(
        'confirmPassword ne correspond pas → error sans appel repo',
        () async {
          final repo = _FakeAuthRepository();
          final ctrl = _makeController(repo);
          await ctrl.submit(
            currentPassword: 'OldPassword1',
            newPassword: 'NewPassword2',
            confirmPassword: 'Different3',
          );
          expect(repo.reauthenticateCalled, isFalse);
          expect(
            _errorMsg(ctrl.state),
            'Les mots de passe ne correspondent pas',
          );
        },
      );

      test(
        'nouveau mot de passe == mot de passe actuel → refusé sans appel repo',
        () async {
          final repo = _FakeAuthRepository();
          final ctrl = _makeController(repo);
          await ctrl.submit(
            currentPassword: 'SamePassword1',
            newPassword: 'SamePassword1',
            confirmPassword: 'SamePassword1',
          );
          expect(repo.reauthenticateCalled, isFalse);
          expect(repo.updatePasswordCalled, isFalse);
          expect(_isError(ctrl.state), isTrue);
          expect(
            _errorMsg(ctrl.state),
            'Le nouveau mot de passe doit être différent de l\'actuel.',
          );
        },
      );

      test(
        'ordre de validation : mot de passe faible détecté avant confirmation différente',
        () async {
          final repo = _FakeAuthRepository();
          final ctrl = _makeController(repo);
          await ctrl.submit(
            currentPassword: 'OldPassword1',
            newPassword: 'abc',
            confirmPassword: 'xyz',
          );
          expect(_errorMsg(ctrl.state), '8 caractères minimum');
        },
      );
    });

    group('submit — erreurs Firebase', () {
      test(
        'wrong-password sur reauthenticate → message dédié « Mot de passe actuel incorrect. »',
        () async {
          final repo = _FakeAuthRepository()
            ..reauthenticateError = FirebaseAuthException(
              code: 'wrong-password',
              message: 'wrong password',
            );
          final ctrl = _makeController(repo);
          await ctrl.submit(
            currentPassword: 'WrongPassword1',
            newPassword: 'NewPassword2',
            confirmPassword: 'NewPassword2',
          );
          expect(_isError(ctrl.state), isTrue);
          expect(_errorMsg(ctrl.state), 'Mot de passe actuel incorrect.');
          expect(repo.updatePasswordCalled, isFalse);
        },
      );

      test(
        'invalid-credential sur reauthenticate → même message dédié',
        () async {
          final repo = _FakeAuthRepository()
            ..reauthenticateError = FirebaseAuthException(
              code: 'invalid-credential',
              message: 'invalid credential',
            );
          final ctrl = _makeController(repo);
          await ctrl.submit(
            currentPassword: 'WrongPassword1',
            newPassword: 'NewPassword2',
            confirmPassword: 'NewPassword2',
          );
          expect(_errorMsg(ctrl.state), 'Mot de passe actuel incorrect.');
          expect(repo.updatePasswordCalled, isFalse);
        },
      );

      test('too-many-requests → mappé via AuthErrorMapper générique', () async {
        final repo = _FakeAuthRepository()
          ..reauthenticateError = FirebaseAuthException(
            code: 'too-many-requests',
            message: 'too many requests',
          );
        final ctrl = _makeController(repo);
        await ctrl.submit(
          currentPassword: 'OldPassword1',
          newPassword: 'NewPassword2',
          confirmPassword: 'NewPassword2',
        );
        expect(
          _errorMsg(ctrl.state),
          'Trop de demandes. Réessayez dans quelques minutes.',
        );
      });

      test(
        'requires-recent-login sur updatePassword → message reconnexion',
        () async {
          final repo = _FakeAuthRepository()
            ..updatePasswordError = FirebaseAuthException(
              code: 'requires-recent-login',
              message: 'requires recent login',
            );
          final ctrl = _makeController(repo);
          await ctrl.submit(
            currentPassword: 'OldPassword1',
            newPassword: 'NewPassword2',
            confirmPassword: 'NewPassword2',
          );
          expect(repo.reauthenticateCalled, isTrue);
          expect(_isError(ctrl.state), isTrue);
          expect(
            _errorMsg(ctrl.state),
            'Pour des raisons de sécurité, reconnectez-vous puis réessayez.',
          );
        },
      );

      test('exception inconnue → message générique', () async {
        final repo = _FakeAuthRepository()
          ..reauthenticateError = Exception('network error');
        final ctrl = _makeController(repo);
        await ctrl.submit(
          currentPassword: 'OldPassword1',
          newPassword: 'NewPassword2',
          confirmPassword: 'NewPassword2',
        );
        expect(
          _errorMsg(ctrl.state),
          'Une erreur est survenue. Veuillez réessayer.',
        );
      });
    });

    group('reset', () {
      test('reset() remet l\'état à idle après un succès', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.submit(
          currentPassword: 'OldPassword1',
          newPassword: 'NewPassword2',
          confirmPassword: 'NewPassword2',
        );
        expect(_isSuccess(ctrl.state), isTrue);

        ctrl.reset();
        expect(ctrl.state, const ChangePasswordState.idle());
      });
    });
  });
}
