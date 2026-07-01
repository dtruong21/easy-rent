import 'package:easyrent/features/auth/data/apple_auth_exception.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/presentation/login_page.dart';
import 'package:easyrent/features/auth/presentation/widgets/apple_sign_in_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  Exception? signInWithAppleError;

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
  Future<void> signInWithApple() async {
    if (signInWithAppleError != null) throw signInWithAppleError!;
  }

  @override
  Future<void> signUpWithApple({required bool rgpdConsent}) async {}

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
  group('LoginForm — bouton Apple et CTA contextuel', () {
    testWidgets('AppleSignInButton actif par défaut (pas de gate)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final appleBtn = tester.widget<AppleSignInButton>(
        find.byType(AppleSignInButton),
      );
      expect(appleBtn.onPressed, isNotNull);
    });

    testWidgets(
      'baillan/apple-new-user-on-login affiche le CTA "Créer un compte"',
      (tester) async {
        final repo = _FakeAuthRepository()
          ..signInWithAppleError = FirebaseAuthException(
            code: AppleAuthErrorCode.newUserOnLogin,
            message: 'No Baillan account for this Apple account.',
          );
        await tester.pumpWidget(_buildLoginPage(repo: repo));
        await tester.pumpAndSettle();

        // Le concept "La Page du Registre" ajoute du chrome au-dessus du
        // form — AppleSignInButton peut se retrouver sous le fold du
        // viewport de test 800x600. ensureVisible scroll avant tap.
        final btnFinder = find.byType(AppleSignInButton);
        await tester.ensureVisible(btnFinder);
        await tester.pumpAndSettle();
        await tester.tap(btnFinder);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Aucun compte Baillan associé à cet Apple. '
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
        ..signInWithAppleError = FirebaseAuthException(
          code: AppleAuthErrorCode.newUserOnLogin,
          message: 'No Baillan account for this Apple account.',
        );
      await tester.pumpWidget(_buildLoginPage(repo: repo));
      await tester.pumpAndSettle();

      final btnFinder = find.byType(AppleSignInButton);
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
