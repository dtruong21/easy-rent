import 'package:easyrent/features/auth/application/reset_password_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/reset_password_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  bool updatePasswordCalled = false;
  Exception? updateError;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;

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
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> updatePassword(String newPassword) async {
    updatePasswordCalled = true;
    if (updateError != null) throw updateError!;
  }

  @override
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ResetPasswordController', () {
    test('état initial est idle', () {
      final ctrl = _makeController(_FakeAuthRepository());
      expect(ctrl.state, const ResetPasswordState.idle());
    });

    group('updatePassword — chemin nominal', () {
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
            .updatePassword(
              newPassword: 'Password1',
              confirmPassword: 'Password1',
            );

        expect(states[0], const ResetPasswordState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
        );
        expect(_isSuccess(states[2]), isTrue);
        expect(repo.updatePasswordCalled, isTrue);
      });
    });

    group('updatePassword — validation', () {
      test('mot de passe trop court → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.updatePassword(newPassword: 'abc', confirmPassword: 'abc');
        expect(repo.updatePasswordCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), '8 caractères minimum');
      });

      test('mot de passe sans chiffre → error', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.updatePassword(
          newPassword: 'abcdefgh',
          confirmPassword: 'abcdefgh',
        );
        expect(repo.updatePasswordCalled, isFalse);
        expect(_errorMsg(ctrl.state), 'Au moins un chiffre');
      });

      test(
        'confirmPassword ne correspond pas → error sans appel repo',
        () async {
          final repo = _FakeAuthRepository();
          final ctrl = _makeController(repo);
          await ctrl.updatePassword(
            newPassword: 'Password1',
            confirmPassword: 'Password2',
          );
          expect(repo.updatePasswordCalled, isFalse);
          expect(
            _errorMsg(ctrl.state),
            'Les mots de passe ne correspondent pas',
          );
        },
      );
    });

    group('updatePassword — erreurs Supabase', () {
      test('otp_expired → lien expiré', () async {
        final repo = _FakeAuthRepository()
          ..updateError = AuthException('Token expired', code: 'otp_expired');
        final ctrl = _makeController(repo);
        await ctrl.updatePassword(
          newPassword: 'Password1',
          confirmPassword: 'Password1',
        );
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), contains('expiré'));
      });

      test('exception inconnue → message générique', () async {
        final repo = _FakeAuthRepository()
          ..updateError = Exception('network error');
        final ctrl = _makeController(repo);
        await ctrl.updatePassword(
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
