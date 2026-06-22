import 'package:easyrent/features/auth/application/signup_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/signup_page_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  bool signUpCalled = false;
  String? lastEmail;
  String? lastFullName;
  Exception? signUpError;

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
  }) async {
    signUpCalled = true;
    lastEmail = email;
    lastFullName = fullName;
    if (signUpError != null) throw signUpError!;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SignupController _makeController(_FakeAuthRepository repo) {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
  );
  return container.read(signupControllerProvider.notifier);
}

bool _isError(SignupPageState s) =>
    s.maybeWhen(error: (_) => true, orElse: () => false);

bool _isAwaiting(SignupPageState s) =>
    s.maybeWhen(awaitingConfirmation: () => true, orElse: () => false);

String _errorMsg(SignupPageState s) =>
    s.maybeWhen(error: (m) => m, orElse: () => '');

const _validSignup = (
  fullName: 'Jean Dupont',
  email: 'jean@exemple.fr',
  password: 'Password1',
  confirmPassword: 'Password1',
  rgpdConsent: true,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SignupController', () {
    test('état initial est idle', () {
      final ctrl = _makeController(_FakeAuthRepository());
      expect(ctrl.state, const SignupPageState.idle());
    });

    group('signUp — chemin nominal', () {
      test('transitions idle → submitting → awaitingConfirmation', () async {
        final repo = _FakeAuthRepository();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final states = <SignupPageState>[];
        container.listen<SignupPageState>(
          signupControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        await container
            .read(signupControllerProvider.notifier)
            .signUp(
              fullName: _validSignup.fullName,
              email: _validSignup.email,
              password: _validSignup.password,
              confirmPassword: _validSignup.confirmPassword,
              rgpdConsent: _validSignup.rgpdConsent,
            );

        expect(states[0], const SignupPageState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
        );
        expect(_isAwaiting(states[2]), isTrue);
        expect(repo.signUpCalled, isTrue);
        expect(repo.lastEmail, _validSignup.email);
        expect(repo.lastFullName, _validSignup.fullName);
      });

      test('trimme email et fullName', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signUp(
          fullName: '  Jean Dupont  ',
          email: '  jean@exemple.fr  ',
          password: 'Password1',
          confirmPassword: 'Password1',
          rgpdConsent: true,
        );
        expect(repo.lastEmail, 'jean@exemple.fr');
        expect(repo.lastFullName, 'Jean Dupont');
      });
    });

    group('signUp — validation', () {
      test('fullName vide → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signUp(
          fullName: '',
          email: _validSignup.email,
          password: _validSignup.password,
          confirmPassword: _validSignup.confirmPassword,
          rgpdConsent: true,
        );
        expect(repo.signUpCalled, isFalse);
        expect(_errorMsg(ctrl.state), 'Nom complet requis');
      });

      test('email invalide → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signUp(
          fullName: _validSignup.fullName,
          email: 'bademail',
          password: _validSignup.password,
          confirmPassword: _validSignup.confirmPassword,
          rgpdConsent: true,
        );
        expect(repo.signUpCalled, isFalse);
        expect(_errorMsg(ctrl.state), 'Adresse email invalide');
      });

      test('mot de passe trop court → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signUp(
          fullName: _validSignup.fullName,
          email: _validSignup.email,
          password: 'abc',
          confirmPassword: 'abc',
          rgpdConsent: true,
        );
        expect(repo.signUpCalled, isFalse);
        expect(_errorMsg(ctrl.state), '8 caractères minimum');
      });

      test('mots de passe non identiques → error', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signUp(
          fullName: _validSignup.fullName,
          email: _validSignup.email,
          password: 'Password1',
          confirmPassword: 'Password2',
          rgpdConsent: true,
        );
        expect(repo.signUpCalled, isFalse);
        expect(_errorMsg(ctrl.state), 'Les mots de passe ne correspondent pas');
      });

      test('RGPD non coché → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signUp(
          fullName: _validSignup.fullName,
          email: _validSignup.email,
          password: _validSignup.password,
          confirmPassword: _validSignup.confirmPassword,
          rgpdConsent: false,
        );
        expect(repo.signUpCalled, isFalse);
        expect(
          _errorMsg(ctrl.state),
          'Vous devez accepter la politique de confidentialité',
        );
      });
    });

    group('signUp — erreurs Supabase', () {
      test('user_already_exists → message français', () async {
        final repo = _FakeAuthRepository()
          ..signUpError = AuthException(
            'User already registered',
            code: 'user_already_exists',
          );
        final ctrl = _makeController(repo);
        await ctrl.signUp(
          fullName: _validSignup.fullName,
          email: _validSignup.email,
          password: _validSignup.password,
          confirmPassword: _validSignup.confirmPassword,
          rgpdConsent: true,
        );
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), contains('Un compte existe déjà'));
      });

      test('exception inconnue → message générique', () async {
        final repo = _FakeAuthRepository()
          ..signUpError = Exception('network error');
        final ctrl = _makeController(repo);
        await ctrl.signUp(
          fullName: _validSignup.fullName,
          email: _validSignup.email,
          password: _validSignup.password,
          confirmPassword: _validSignup.confirmPassword,
          rgpdConsent: true,
        );
        expect(
          _errorMsg(ctrl.state),
          'Une erreur est survenue. Veuillez réessayer.',
        );
      });
    });
  });
}
