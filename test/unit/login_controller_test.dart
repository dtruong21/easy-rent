import 'package:easyrent/features/auth/application/login_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/login_page_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  bool signInCalled = false;
  bool signOutCalled = false;
  String? lastEmail;
  Exception? signInError;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;

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
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}

class _ThrowingSignOutRepo extends _FakeAuthRepository {
  @override
  Future<void> signOut() async => throw Exception('signOut failed');
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
    s.maybeWhen(error: (_) => true, orElse: () => false);

String _errorMsg(LoginPageState s) =>
    s.maybeWhen(error: (m) => m, orElse: () => '');

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
        expect(_errorMsg(ctrl.state), 'Adresse email invalide');
      });

      test('mot de passe vide → error sans appel repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: 'user@exemple.fr', password: '');
        expect(repo.signInCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(_errorMsg(ctrl.state), 'Mot de passe requis');
      });
    });

    group('signIn — erreurs Supabase', () {
      test('invalid_credentials → message français', () async {
        final repo = _FakeAuthRepository()
          ..signInError = AuthException(
            'Invalid login credentials',
            code: 'invalid_credentials',
          );
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: 'user@exemple.fr', password: 'Password1');
        expect(_errorMsg(ctrl.state), 'Email ou mot de passe incorrect.');
      });

      test('email_not_confirmed → message français', () async {
        final repo = _FakeAuthRepository()
          ..signInError = AuthException(
            'Email not confirmed',
            code: 'email_not_confirmed',
          );
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: 'user@exemple.fr', password: 'Password1');
        expect(_errorMsg(ctrl.state), contains('Vérifiez votre email'));
      });

      test('exception inconnue → message générique', () async {
        final repo = _FakeAuthRepository()
          ..signInError = Exception('network error');
        final ctrl = _makeController(repo);
        await ctrl.signIn(email: 'user@exemple.fr', password: 'Password1');
        expect(
          _errorMsg(ctrl.state),
          'Une erreur est survenue. Veuillez réessayer.',
        );
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
