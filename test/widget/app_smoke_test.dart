import 'package:easyrent/features/auth/application/login_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/login_page_state.dart';
import 'package:easyrent/features/auth/presentation/login_page.dart';
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
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Helper de montage : injecte le faux repo dans le ProviderScope.
// ---------------------------------------------------------------------------
Widget _buildApp(Widget child) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
    ],
    child: MaterialApp(home: child),
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
      expect(
        find.text('Connectez-vous pour gérer vos locations'),
        findsOneWidget,
      );
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
          child: const MaterialApp(home: LoginPage()),
        ),
      );
      await tester.pump();

      expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
    });
  });
}
