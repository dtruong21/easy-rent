import 'package:easyrent/features/auth/application/reset_password_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/reset_password_state.dart';
import 'package:easyrent/features/auth/presentation/reset_password_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repo (Firebase)
//
// La page de reset-password lit `oobCode` dans Uri.base.queryParameters
// — pas testable sans manipuler Uri.base. Ce fichier teste donc :
//   * l'affichage de _InvalidLinkView quand oobCode est absent (cas par
//     défaut dans l'environnement de test)
//   * la navigation des boutons "Demander un nouveau lien" / "Retour"
//   * l'état submitting (controller surchargé)
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async =>
      null;

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {}

  @override
  Future<void> deleteAccount() async {}

  Exception? confirmError;

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
  }) async {
    if (confirmError != null) throw confirmError!;
  }

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

Widget _buildPage({
  required _FakeAuthRepository repo,
  ResetPasswordState? initialState,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ResetPasswordPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Text('Page connexion')),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) =>
            const Scaffold(body: Text('Mot de passe oublié')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      if (initialState != null)
        resetPasswordControllerProvider.overrideWith(
          (ref) =>
              ResetPasswordController(ref.read(authRepositoryProvider))
                ..state = initialState,
        ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
    ),
  );
}

void main() {
  group('ResetPasswordPage', () {
    testWidgets('affiche _InvalidLinkView quand pas de oobCode dans l\'URL', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Lien invalide ou expiré'), findsOneWidget);
      expect(find.text('Demander un nouveau lien'), findsOneWidget);
    });

    testWidgets('"Demander un nouveau lien" navigue vers /forgot-password', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Demander un nouveau lien'));
      await tester.pumpAndSettle();

      expect(find.text('Mot de passe oublié'), findsOneWidget);
    });

    testWidgets('"Retour à la connexion" navigue vers /login', (tester) async {
      await tester.pumpWidget(_buildPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retour à la connexion'));
      await tester.pumpAndSettle();

      expect(find.text('Page connexion'), findsOneWidget);
    });
  });
}
