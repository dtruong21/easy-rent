import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/data/google_auth_exception.dart';
import 'package:easyrent/features/auth/presentation/login_page.dart';
import 'package:easyrent/features/auth/presentation/widgets/google_sign_in_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async =>
      null;

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {}

  @override
  Future<void> deleteAccount() async {}

  Exception? signInWithGoogleError;

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
  Future<void> signInWithGoogle() async {
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
  Future<void> signOut() async {}

  @override
  Future<void> reauthenticateWithPassword(String currentPassword) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildLoginPage({required _FakeAuthRepository repo}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/signup',
        builder: (context, state) =>
            const Scaffold(body: Text('Page inscription')),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) =>
            const Scaffold(body: Text('Mot de passe oublié')),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) =>
            const Scaffold(body: Text('Politique de confidentialité')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LoginForm — bouton Google et CTA contextuel', () {
    testWidgets('GoogleSignInButton actif par défaut (pas de gate)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final googleBtn = tester.widget<GoogleSignInButton>(
        find.byType(GoogleSignInButton),
      );
      expect(googleBtn.onPressed, isNotNull);
    });

    testWidgets(
      'baillan/google-new-user-on-login affiche le CTA "Créer un compte"',
      (tester) async {
        final repo = _FakeAuthRepository()
          ..signInWithGoogleError = FirebaseAuthException(
            code: GoogleAuthErrorCode.newUserOnLogin,
            message: 'No Baillan account for this Google account.',
          );
        await tester.pumpWidget(_buildLoginPage(repo: repo));
        await tester.pumpAndSettle();

        // Le concept "La Page du Registre" ajoute du chrome au-dessus du
        // form — GoogleSignInButton peut se retrouver sous le fold du
        // viewport de test 800x600. ensureVisible scroll avant tap.
        final btnFinder = find.byType(GoogleSignInButton);
        await tester.ensureVisible(btnFinder);
        await tester.pumpAndSettle();
        await tester.tap(btnFinder);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Aucun compte Baillan associé à ce Google. '
            'Veuillez d\'abord créer un compte.',
          ),
          findsOneWidget,
        );
        // Le CTA d'erreur est ciblé par sa Key (le libellé "Créer un compte"
        // existe aussi sur le lien de navigation classique du formulaire).
        expect(find.byKey(const Key('login_error_cta_button')), findsOneWidget);
      },
    );

    testWidgets('tap sur le CTA "Créer un compte" route vers /signup', (
      tester,
    ) async {
      final repo = _FakeAuthRepository()
        ..signInWithGoogleError = FirebaseAuthException(
          code: GoogleAuthErrorCode.newUserOnLogin,
          message: 'No Baillan account for this Google account.',
        );
      await tester.pumpWidget(_buildLoginPage(repo: repo));
      await tester.pumpAndSettle();

      final btnFinder = find.byType(GoogleSignInButton);
      await tester.ensureVisible(btnFinder);
      await tester.pumpAndSettle();
      await tester.tap(btnFinder);
      await tester.pumpAndSettle();

      final ctaFinder = find.byKey(const Key('login_error_cta_button'));
      await tester.ensureVisible(ctaFinder);
      await tester.pumpAndSettle();
      await tester.tap(ctaFinder);
      await tester.pumpAndSettle();

      expect(find.text('Page inscription'), findsOneWidget);
    });
  });
}
