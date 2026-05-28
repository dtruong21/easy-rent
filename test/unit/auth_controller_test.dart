import 'package:easyrent/features/auth/application/auth_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/login_form_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake repository — aucun appel réseau.
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  bool sendMagicLinkCalled = false;
  bool signOutCalled = false;
  String? lastEmail;
  Exception? sendError;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;

  @override
  Future<void> sendMagicLink(String email) async {
    sendMagicLinkCalled = true;
    lastEmail = email;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}

// ---------------------------------------------------------------------------
// Helpers pour inspecter les états freezed scellés.
// ---------------------------------------------------------------------------

bool _isError(LoginFormState s) =>
    s.maybeWhen(error: (_) => true, orElse: () => false);

bool _isLinkSent(LoginFormState s) =>
    s.maybeWhen(linkSent: (_) => true, orElse: () => false);

String _errorMessage(LoginFormState s) =>
    s.maybeWhen(error: (msg) => msg, orElse: () => '');

String _linkSentEmail(LoginFormState s) =>
    s.maybeWhen(linkSent: (email) => email, orElse: () => '');

// ---------------------------------------------------------------------------
// Helper — crée un AuthController avec un repo injecté.
// ---------------------------------------------------------------------------

AuthController _makeController(
  _FakeAuthRepository repo, {
  ProviderContainer? container,
}) {
  final c =
      container ??
      ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
  return c.read(authControllerProvider.notifier);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AuthController', () {
    // -----------------------------------------------------------------------
    // Transition idle → submitting → linkSent (chemin nominal)
    // -----------------------------------------------------------------------
    group('sendMagicLink — chemin nominal', () {
      test('transitions idle → submitting → linkSent', () async {
        final repo = _FakeAuthRepository();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repo)],
        );
        addTearDown(container.dispose);

        final states = <LoginFormState>[];
        container.listen<LoginFormState>(
          authControllerProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );

        await container
            .read(authControllerProvider.notifier)
            .sendMagicLink(email: 'user@exemple.fr', rgpdConsent: true);

        expect(states[0], const LoginFormState.idle());
        expect(
          states[1].maybeWhen(submitting: () => true, orElse: () => false),
          isTrue,
          reason: 'Le deuxième état doit être submitting',
        );
        expect(_isLinkSent(states[2]), isTrue);
        expect(_linkSentEmail(states[2]), 'user@exemple.fr');
        expect(repo.sendMagicLinkCalled, isTrue);
        expect(repo.lastEmail, 'user@exemple.fr');
      });

      test("trimme l'email avant de l'envoyer au repo", () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.sendMagicLink(
          email: '  user@exemple.fr  ',
          rgpdConsent: true,
        );
        expect(repo.lastEmail, 'user@exemple.fr');
        expect(_isLinkSent(ctrl.state), isTrue);
        expect(_linkSentEmail(ctrl.state), 'user@exemple.fr');
      });
    });

    // -----------------------------------------------------------------------
    // Chemin erreur — AuthException supabase
    // -----------------------------------------------------------------------
    group('sendMagicLink — chemin erreur', () {
      test(
        'passe à error quand le repo lève une AuthException générique',
        () async {
          final repo = _FakeAuthRepository()
            ..sendError = AuthException('something went wrong');
          final ctrl = _makeController(repo);
          await ctrl.sendMagicLink(email: 'user@exemple.fr', rgpdConsent: true);
          expect(_isError(ctrl.state), isTrue);
          expect(
            _errorMessage(ctrl.state),
            "Impossible d'envoyer le lien. Vérifiez votre email et réessayez.",
          );
        },
      );

      test('message "rate limit" est traduit en français', () async {
        final repo = _FakeAuthRepository()
          ..sendError = AuthException('rate limit exceeded');
        final ctrl = _makeController(repo);
        await ctrl.sendMagicLink(email: 'user@exemple.fr', rgpdConsent: true);
        expect(_errorMessage(ctrl.state), contains('Trop de demandes'));
      });

      test('message "invalid email" supabase est traduit', () async {
        final repo = _FakeAuthRepository()
          ..sendError = AuthException('invalid email format');
        final ctrl = _makeController(repo);
        await ctrl.sendMagicLink(email: 'user@exemple.fr', rgpdConsent: true);
        expect(_errorMessage(ctrl.state), 'Adresse email invalide');
      });

      test('exception inconnue → message générique', () async {
        final repo = _FakeAuthRepository()
          ..sendError = Exception('network error');
        final ctrl = _makeController(repo);
        await ctrl.sendMagicLink(email: 'user@exemple.fr', rgpdConsent: true);
        expect(
          _errorMessage(ctrl.state),
          "Une erreur est survenue. Veuillez réessayer.",
        );
      });
    });

    // -----------------------------------------------------------------------
    // Gating email invalide — aucun appel repo
    // -----------------------------------------------------------------------
    group('sendMagicLink — gating email invalide', () {
      final invalidEmails = [
        '',
        '   ',
        'notanemail',
        '@nodomain.com',
        'user@',
        'user name@example.com',
      ];

      for (final email in invalidEmails) {
        test('rejette "$email" sans appeler le repo', () async {
          final repo = _FakeAuthRepository();
          final ctrl = _makeController(repo);
          await ctrl.sendMagicLink(email: email, rgpdConsent: true);
          expect(repo.sendMagicLinkCalled, isFalse);
          expect(_isError(ctrl.state), isTrue);
          expect(_errorMessage(ctrl.state), 'Adresse email invalide');
        });
      }
    });

    // -----------------------------------------------------------------------
    // Gating consentement RGPD non coché — aucun appel repo
    // -----------------------------------------------------------------------
    group('sendMagicLink — gating RGPD', () {
      test('rejette quand rgpdConsent = false sans appeler le repo', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.sendMagicLink(email: 'user@exemple.fr', rgpdConsent: false);
        expect(repo.sendMagicLinkCalled, isFalse);
        expect(_isError(ctrl.state), isTrue);
        expect(
          _errorMessage(ctrl.state),
          'Vous devez accepter la politique de confidentialité',
        );
      });

      test('gating email invalide a priorité sur gating RGPD', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.sendMagicLink(email: 'bademail', rgpdConsent: false);
        expect(repo.sendMagicLinkCalled, isFalse);
        expect(_errorMessage(ctrl.state), 'Adresse email invalide');
      });
    });

    // -----------------------------------------------------------------------
    // reset — renvoi de lien (bouton "Renvoyer un lien")
    // -----------------------------------------------------------------------
    group('reset', () {
      test('repasse à idle depuis linkSent', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        await ctrl.sendMagicLink(email: 'user@exemple.fr', rgpdConsent: true);
        expect(_isLinkSent(ctrl.state), isTrue);
        ctrl.reset();
        expect(ctrl.state, const LoginFormState.idle());
      });

      test('repasse à idle depuis error', () async {
        final repo = _FakeAuthRepository()..sendError = AuthException('fail');
        final ctrl = _makeController(repo);
        await ctrl.sendMagicLink(email: 'user@exemple.fr', rgpdConsent: true);
        expect(_isError(ctrl.state), isTrue);
        ctrl.reset();
        expect(ctrl.state, const LoginFormState.idle());
      });
    });

    // -----------------------------------------------------------------------
    // signOut
    // -----------------------------------------------------------------------
    group('signOut', () {
      test('appelle signOut sur le repo et repasse à idle', () async {
        final repo = _FakeAuthRepository();
        final ctrl = _makeController(repo);
        // Mettre d'abord en linkSent pour vérifier le reset.
        await ctrl.sendMagicLink(email: 'user@exemple.fr', rgpdConsent: true);
        await ctrl.signOut();
        expect(repo.signOutCalled, isTrue);
        expect(ctrl.state, const LoginFormState.idle());
      });

      test(
        'repasse à idle même si le repo lève une exception (finally)',
        () async {
          // On crée un repo dont signOut lève une exception.
          final repo = _ThrowingSignOutRepo();
          final container = ProviderContainer(
            overrides: [authRepositoryProvider.overrideWithValue(repo)],
          );
          addTearDown(container.dispose);
          final ctrl = container.read(authControllerProvider.notifier);
          await ctrl.signOut();
          expect(ctrl.state, const LoginFormState.idle());
        },
      );
    });

    // -----------------------------------------------------------------------
    // État initial
    // -----------------------------------------------------------------------
    test('état initial est idle', () {
      final repo = _FakeAuthRepository();
      final ctrl = _makeController(repo);
      expect(ctrl.state, const LoginFormState.idle());
    });
  });
}

// Repo dont signOut lève toujours une exception (test finally).
class _ThrowingSignOutRepo implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
  @override
  Session? get currentSession => null;
  @override
  Future<void> sendMagicLink(String email) async {}
  @override
  Future<void> signOut() async => throw Exception('signOut failed');
}
