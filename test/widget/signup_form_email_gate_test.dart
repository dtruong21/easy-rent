import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/presentation/signup_page.dart';
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

  bool signUpWithPasswordCalled = false;

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
  }) async {
    signUpWithPasswordCalled = true;
  }

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

/// Remplit les 4 champs avec des valeurs valides (nom, email, password ×2)
/// SANS cocher la case RGPD — reproduit l'état où seul `_ensureConsent` doit
/// bloquer la soumission (le controller a sa propre défense en profondeur,
/// testée séparément dans `signup_controller_test.dart`).
Future<void> _fillValidFieldsWithoutConsent(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'Jean Dupont');
  await tester.enterText(fields.at(1), 'jean@exemple.fr');
  await tester.enterText(fields.at(2), 'Password1');
  await tester.enterText(fields.at(3), 'Password1');
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SignupForm — gate email/password sur consentement RGPD', () {
    testWidgets(
      'tap "Créer mon compte" (champs valides, case décochée) → erreur '
      'près de la checkbox, signUpWithPassword PAS appelé',
      (tester) async {
        final repo = _FakeAuthRepository();
        await tester.pumpWidget(_buildSignupPage(repo: repo));
        await tester.pumpAndSettle();

        await _fillValidFieldsWithoutConsent(tester);

        // Le bouton reste cliquable sans consentement (un bouton mort sans
        // explication n'est pas compris) : le clic explique au lieu de
        // soumettre. _canSubmit ne dépend plus de _rgpdConsent depuis
        // d9ad603 — seul _ensureConsent() doit bloquer ici.
        final createAccountButton = find.widgetWithText(
          FilledButton,
          'Créer mon compte',
        );
        await tester.ensureVisible(createAccountButton);
        await tester.tap(createAccountButton);
        await tester.pumpAndSettle();

        expect(repo.signUpWithPasswordCalled, isFalse);
        expect(find.byKey(const Key('rgpd_consent_error')), findsOneWidget);
      },
    );

    testWidgets('cocher la case après une erreur de consentement l\'efface', (
      tester,
    ) async {
      final repo = _FakeAuthRepository();
      await tester.pumpWidget(_buildSignupPage(repo: repo));
      await tester.pumpAndSettle();

      await _fillValidFieldsWithoutConsent(tester);

      final createAccountButton = find.widgetWithText(
        FilledButton,
        'Créer mon compte',
      );
      await tester.ensureVisible(createAccountButton);
      await tester.tap(createAccountButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rgpd_consent_error')), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rgpd_consent_error')), findsNothing);
    });

    testWidgets('champs valides + case cochée → tap "Créer mon compte" appelle '
        'signUpWithPassword', (tester) async {
      final repo = _FakeAuthRepository();
      await tester.pumpWidget(_buildSignupPage(repo: repo));
      await tester.pumpAndSettle();

      await _fillValidFieldsWithoutConsent(tester);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final createAccountButton = find.widgetWithText(
        FilledButton,
        'Créer mon compte',
      );
      await tester.ensureVisible(createAccountButton);
      await tester.tap(createAccountButton);
      await tester.pumpAndSettle();

      expect(repo.signUpWithPasswordCalled, isTrue);
    });
  });
}
