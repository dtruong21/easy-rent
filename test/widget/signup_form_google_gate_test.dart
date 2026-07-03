import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/data/google_auth_exception.dart';
import 'package:easyrent/features/auth/presentation/signup_page.dart';
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
  bool signUpWithGoogleCalled = false;
  bool? lastRgpdConsent;
  Exception? signUpWithGoogleError;

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
  Future<void> signUpWithGoogle({required bool rgpdConsent}) async {
    signUpWithGoogleCalled = true;
    lastRgpdConsent = rgpdConsent;
    if (signUpWithGoogleError != null) throw signUpWithGoogleError!;
  }

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

Widget _buildSignupPage({required _FakeAuthRepository repo}) {
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
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SignupForm — gate Google sur consentement RGPD', () {
    testWidgets('tap Google sans consentement → erreur près de la checkbox, '
        'signUpWithGoogle PAS appelé, cocher la case efface l\'erreur', (
      tester,
    ) async {
      final repo = _FakeAuthRepository();
      await tester.pumpWidget(_buildSignupPage(repo: repo));
      await tester.pumpAndSettle();

      // Le bouton reste cliquable sans consentement (un bouton mort sans
      // explication n'est pas compris) : le clic explique au lieu de
      // soumettre.
      await tester.ensureVisible(find.byType(GoogleSignInButton));
      await tester.tap(find.byType(GoogleSignInButton));
      await tester.pumpAndSettle();

      expect(repo.signUpWithGoogleCalled, isFalse);
      expect(find.byKey(const Key('rgpd_consent_error')), findsOneWidget);

      // Cocher la case résout l'erreur.
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rgpd_consent_error')), findsNothing);
    });

    testWidgets('cocher la case RGPD active le bouton Google', (tester) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final googleBtn = tester.widget<GoogleSignInButton>(
        find.byType(GoogleSignInButton),
      );
      expect(googleBtn.onPressed, isNotNull);
    });

    testWidgets(
      'tap sur le bouton actif appelle signUpWithGoogle(rgpdConsent: true)',
      (tester) async {
        final repo = _FakeAuthRepository();
        await tester.pumpWidget(_buildSignupPage(repo: repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        await tester.ensureVisible(find.byType(GoogleSignInButton));
        await tester.tap(find.byType(GoogleSignInButton));
        await tester.pump();

        expect(repo.signUpWithGoogleCalled, isTrue);
        expect(repo.lastRgpdConsent, isTrue);
      },
    );

    testWidgets(
      'si le repo throw rgpd-consent-declined, le message FR s\'affiche',
      (tester) async {
        final repo = _FakeAuthRepository()
          ..signUpWithGoogleError = FirebaseAuthException(
            code: GoogleAuthErrorCode.consentDeclined,
            message: 'RGPD consent not given.',
          );
        await tester.pumpWidget(_buildSignupPage(repo: repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        await tester.ensureVisible(find.byType(GoogleSignInButton));
        await tester.tap(find.byType(GoogleSignInButton));
        await tester.pumpAndSettle();

        expect(
          find.text(
            "Vous devez accepter les conditions générales d'utilisation "
            'et la politique de confidentialité.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
