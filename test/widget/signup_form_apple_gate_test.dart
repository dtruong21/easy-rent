import 'package:easyrent/features/auth/data/apple_auth_exception.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/presentation/signup_page.dart';
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
  bool signUpWithAppleCalled = false;
  bool? lastRgpdConsent;
  Exception? signUpWithAppleError;

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
  Future<void> signInWithApple() async {}

  @override
  Future<void> signUpWithApple({required bool rgpdConsent}) async {
    signUpWithAppleCalled = true;
    lastRgpdConsent = rgpdConsent;
    if (signUpWithAppleError != null) throw signUpWithAppleError!;
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
  group('SignupForm — gate Apple sur consentement RGPD', () {
    testWidgets(
      'AppleSignInButton.onPressed est null tant que la checkbox RGPD '
      'n\'est pas cochée',
      (tester) async {
        await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
        await tester.pumpAndSettle();

        final appleBtn = tester.widget<AppleSignInButton>(
          find.byType(AppleSignInButton),
        );
        expect(appleBtn.onPressed, isNull);
      },
    );

    testWidgets('cocher la case RGPD active le bouton Apple', (tester) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final appleBtn = tester.widget<AppleSignInButton>(
        find.byType(AppleSignInButton),
      );
      expect(appleBtn.onPressed, isNotNull);
    });

    testWidgets(
      'tap sur le bouton actif appelle signUpWithApple(rgpdConsent: true)',
      (tester) async {
        final repo = _FakeAuthRepository();
        await tester.pumpWidget(_buildSignupPage(repo: repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        await tester.ensureVisible(find.byType(AppleSignInButton));
        await tester.tap(find.byType(AppleSignInButton));
        await tester.pump();

        expect(repo.signUpWithAppleCalled, isTrue);
        expect(repo.lastRgpdConsent, isTrue);
      },
    );

    testWidgets(
      'si le repo throw rgpd-consent-declined, le message FR s\'affiche',
      (tester) async {
        final repo = _FakeAuthRepository()
          ..signUpWithAppleError = FirebaseAuthException(
            code: AppleAuthErrorCode.consentDeclined,
            message: 'RGPD consent not given.',
          );
        await tester.pumpWidget(_buildSignupPage(repo: repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox));
        await tester.pump();

        await tester.ensureVisible(find.byType(AppleSignInButton));
        await tester.tap(find.byType(AppleSignInButton));
        await tester.pumpAndSettle();

        expect(
          find.text('Vous devez accepter la politique de confidentialité.'),
          findsOneWidget,
        );
      },
    );
  });
}
