import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/features/auth/application/login_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/login_page_state.dart';
import 'package:easyrent/features/auth/presentation/login_page.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// Faux repository — aucun appel réseau.
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
// Helper de montage : injecte le faux repo dans le ProviderScope.
// ---------------------------------------------------------------------------
Widget _buildApp(Widget child) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
      home: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('LoginPage smoke test', () {
    testWidgets('renders without crash and shows key text', (tester) async {
      await tester.pumpWidget(_buildApp(const LoginPage()));
      await tester.pump();

      expect(find.text('Baillan.'), findsOneWidget);
      // Nouveau design "La Page du Registre" (2026-07-01) : l'aphorisme
      // remplace l'ancien subhead descriptif.
      expect(find.text('En cas de doute, sortez le registre.'), findsOneWidget);
    });

    testWidgets('shows email field and password field', (tester) async {
      await tester.pumpWidget(_buildApp(const LoginPage()));
      await tester.pump();

      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('submit button is disabled when fields are empty', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(const LoginPage()));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'submit button stays disabled when email valid but password empty',
      (tester) async {
        await tester.pumpWidget(_buildApp(const LoginPage()));
        await tester.pump();

        await tester.enterText(find.byType(TextField).first, 'test@exemple.fr');
        await tester.pump();

        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
      },
    );

    testWidgets('shows error message when state is error', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
            loginControllerProvider.overrideWith(
              (ref) => LoginController(ref.read(authRepositoryProvider))
                ..state = const LoginPageState.error(
                  message: 'Email ou mot de passe incorrect.',
                ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: supportedLocales,
            locale: const Locale('fr'),
            home: const LoginPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
    });
  });
}
