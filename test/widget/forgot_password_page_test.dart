import 'package:easyrent/features/auth/application/forgot_password_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/forgot_password_state.dart';
import 'package:easyrent/features/auth/presentation/forgot_password_page.dart';
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
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildPage({
  required _FakeAuthRepository repo,
  ForgotPasswordState? initialState,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Text('Page connexion')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      if (initialState != null)
        forgotPasswordControllerProvider.overrideWith(
          (ref) =>
              ForgotPasswordController(ref.read(authRepositoryProvider))
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
  group('ForgotPasswordPage', () {
    testWidgets('affiche le champ email', (tester) async {
      await tester.pumpWidget(_buildPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Adresse email'), findsOneWidget);
    });

    testWidgets('bouton désactivé par défaut (email vide)', (tester) async {
      await tester.pumpWidget(_buildPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('bouton activé quand email valide', (tester) async {
      await tester.pumpWidget(_buildPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'user@exemple.fr');
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('affiche CircularProgressIndicator en état submitting', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildPage(
          repo: _FakeAuthRepository(),
          initialState: const ForgotPasswordState.submitting(),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('état emailSent affiche PasswordResetSentView', (tester) async {
      await tester.pumpWidget(
        _buildPage(
          repo: _FakeAuthRepository(),
          initialState: const ForgotPasswordState.emailSent(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lien envoyé'), findsOneWidget);
      expect(find.textContaining('boîte mail'), findsOneWidget);
      expect(find.text('Retour à la connexion'), findsOneWidget);
    });

    testWidgets("affiche le message d'erreur en état error", (tester) async {
      await tester.pumpWidget(
        _buildPage(
          repo: _FakeAuthRepository(),
          initialState: const ForgotPasswordState.error(
            message: 'Trop de demandes. Réessayez dans quelques minutes.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Trop de demandes'), findsOneWidget);
    });

    testWidgets('lien "Retour à la connexion" navigue vers /login', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retour à la connexion'));
      await tester.pumpAndSettle();

      expect(find.text('Page connexion'), findsOneWidget);
    });
  });
}
