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
  Future<void> signOut() async {}
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
    testWidgets(
      'GoogleSignInButton.onPressed est null tant que la checkbox RGPD '
      'n\'est pas cochée',
      (tester) async {
        await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
        await tester.pumpAndSettle();

        final googleBtn = tester.widget<GoogleSignInButton>(
          find.byType(GoogleSignInButton),
        );
        expect(googleBtn.onPressed, isNull);
      },
    );

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
          find.text('Vous devez accepter la politique de confidentialité.'),
          findsOneWidget,
        );
      },
    );
  });
}
