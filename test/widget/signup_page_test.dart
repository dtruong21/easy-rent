import 'package:easyrent/features/auth/application/signup_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/signup_page_state.dart';
import 'package:easyrent/features/auth/presentation/signup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
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
  }) async {}

  @override
  Future<void> sendCurrentUserEmailVerification() async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signUpWithApple({required bool rgpdConsent}) async {}

  @override
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildSignupPage({
  required _FakeAuthRepository repo,
  SignupPageState? initialState,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SignupPage()),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Text('Page connexion')),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) =>
            const Scaffold(body: Text('Politique de confidentialité')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      if (initialState != null)
        signupControllerProvider.overrideWith(
          (ref) =>
              SignupController(ref.read(authRepositoryProvider))
                ..state = initialState,
        ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SignupPage', () {
    testWidgets('affiche 4 champs de saisie', (tester) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('affiche la case à cocher RGPD', (tester) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
    });

    testWidgets('bouton désactivé par défaut', (tester) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('affiche CircularProgressIndicator en état submitting', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSignupPage(
          repo: _FakeAuthRepository(),
          initialState: const SignupPageState.submitting(),
        ),
      );
      await tester.pump();

      // Seul le bouton dont la requête est en cours affiche le spinner ;
      // sans clic préalable, `_googleClickedLast` est false donc c'est le
      // FilledButton "Créer mon compte" qui spin. L'autre bouton est
      // désactivé mais ne spin pas.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'état awaitingConfirmation affiche SignupConfirmationSentView',
      (tester) async {
        await tester.pumpWidget(
          _buildSignupPage(
            repo: _FakeAuthRepository(),
            initialState: const SignupPageState.awaitingConfirmation(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Vérifiez votre boîte mail'), findsOneWidget);
        expect(find.text('Retour à la connexion'), findsOneWidget);
      },
    );

    testWidgets('bouton "Retour à la connexion" navigue vers /login', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSignupPage(
          repo: _FakeAuthRepository(),
          initialState: const SignupPageState.awaitingConfirmation(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retour à la connexion'));
      await tester.pumpAndSettle();

      expect(find.text('Page connexion'), findsOneWidget);
    });

    testWidgets("affiche le message d'erreur en état error", (tester) async {
      await tester.pumpWidget(
        _buildSignupPage(
          repo: _FakeAuthRepository(),
          initialState: const SignupPageState.error(
            message: 'Un compte existe déjà avec cet email.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Un compte existe déjà'), findsOneWidget);
    });

    testWidgets('lien "J\'ai déjà un compte" navigue vers /login', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      // Le bouton peut être en-dessous du viewport — on fait défiler.
      await tester.ensureVisible(find.text("J'ai déjà un compte"));
      await tester.tap(find.text("J'ai déjà un compte"));
      await tester.pumpAndSettle();

      expect(find.text('Page connexion'), findsOneWidget);
    });
  });
}
