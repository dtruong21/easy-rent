import 'package:easyrent/features/auth/application/reset_password_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/reset_password_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository (Firebase)
//
// Le nouveau flow est `confirmReset(oobCode, newPassword, confirmPassword)`
// qui appelle confirmPasswordReset côté repo. La validation
// password+confirm reste inchangée, on ne couvre que les chemins du
// controller (pas FirebaseAuth lui-même).
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  bool confirmResetCalled = false;
  String? lastCode;
  Exception? confirmError;

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
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<String> verifyPasswordResetCode(String code) async =>
      'test@example.com';

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    confirmResetCalled = true;
    lastCode = code;
    if (confirmError != null) throw confirmError!;
  }

  @override
  Future<void> signOut() async {}
}

ResetPasswordController _makeController(_FakeAuthRepository repo) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  return container.read(resetPasswordControllerProvider.notifier);
}

bool _isError(ResetPasswordState s) =>
    s.maybeWhen(error: (_) => true, orElse: () => false);

bool _isSuccess(ResetPasswordState s) =>
    s.maybeWhen(success: () => true, orElse: () => false);

String _errorMsg(ResetPasswordState s) =>
    s.maybeWhen(error: (m) => m, orElse: () => '');

const _validCode = 'oob-1234';

void main() {
  group('ResetPasswordController', () {
    test('état initial est idle', () {
      final ctrl = _makeController(_FakeAuthRepository());
      expect(ctrl.state, const ResetPasswordState.idle());
    });

    group('confirmReset — chemin nominal', () {
      test('transitions idle → submitting → success', () async {
        final repo = _FakeAuthRepository();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final states = <ResetPasswordState>[];
        container.listen<ResetPasswordState>(
          resetPasswordControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        await container
            .read(resetPasswordControllerProvider.notifier)
            .confirmReset(
              oobCode: _validCode,
              newPassword: 'Password1',
              confirmPassword: 'Password1',
            );

        expect(states[0], const ResetPasswordState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
        );
        expect(_isSuccess(states[2]), isTrue);
        expect(repo.confirmResetCalled, isTrue);
        expect(repo.lastCode, _validCode);
      });
    });

    group('confirmReset — validation', () {
      test('oobCode vide → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.confirmReset(
          oobCode: '',
          newPassword: 'Password1',
          confirmPassword: 'Password1',
        );
        expect(repo.confirmResetCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), contains('Code'));
      });

      test('mot de passe trop court → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.confirmReset(
          oobCode: _validCode,
          newPassword: 'abc',
          confirmPassword: 'abc',
        );
        expect(repo.confirmResetCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), '8 caractères minimum');
      });

      test('mot de passe sans chiffre → error', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.confirmReset(
          oobCode: _validCode,
          newPassword: 'abcdefgh',
          confirmPassword: 'abcdefgh',
        );
        expect(repo.confirmResetCalled, isFalse);
        expect(_errorMsg(ctrl.state), 'Au moins un chiffre');
      });

      test(
        'confirmPassword ne correspond pas → error sans appel repo',
        () async {
          final repo = _FakeAuthRepository();
          final ctrl = _makeController(repo);
          await ctrl.confirmReset(
            oobCode: _validCode,
            newPassword: 'Password1',
            confirmPassword: 'Password2',
          );
          expect(repo.confirmResetCalled, isFalse);
          expect(
            _errorMsg(ctrl.state),
            'Les mots de passe ne correspondent pas',
          );
        },
      );
    });

    group('confirmReset — erreurs Firebase', () {
      test('expired-action-code → lien expiré', () async {
        final repo = _FakeAuthRepository()
          ..confirmError = FirebaseAuthException(
            code: 'expired-action-code',
            message: 'The action code has expired.',
          );
        final ctrl = _makeController(repo);
        await ctrl.confirmReset(
          oobCode: _validCode,
          newPassword: 'Password1',
          confirmPassword: 'Password1',
        );
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), contains('expiré'));
      });

      test('exception inconnue → message générique', () async {
        final repo = _FakeAuthRepository()
          ..confirmError = Exception('network error');
        final ctrl = _makeController(repo);
        await ctrl.confirmReset(
          oobCode: _validCode,
          newPassword: 'Password1',
          confirmPassword: 'Password1',
        );
        expect(
          _errorMsg(ctrl.state),
          'Une erreur est survenue. Veuillez réessayer.',
        );
      });
    });
  });
}
