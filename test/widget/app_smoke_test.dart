import 'package:easyrent/features/auth/application/auth_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/login_form_state.dart';
import 'package:easyrent/features/auth/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Faux repository — aucun appel réseau.
// ---------------------------------------------------------------------------
class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;

  @override
  Future<void> sendMagicLink(String email) async {}

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

      // Le titre de l'application doit être présent.
      expect(find.text('EasyRent'), findsOneWidget);

      // Le sous-titre de connexion doit être présent (critère FEAT-001).
      expect(
        find.text('Connectez-vous pour gérer vos locations'),
        findsOneWidget,
      );
    });

    testWidgets('shows email field and RGPD checkbox', (tester) async {
      await tester.pumpWidget(_buildApp(const LoginPage()));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('submit button is disabled when email is empty', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(const LoginPage()));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'submit button stays disabled when email valid but RGPD unchecked',
      (tester) async {
        await tester.pumpWidget(_buildApp(const LoginPage()));
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'test@exemple.fr');
        await tester.pump();

        // Case non cochée → bouton désactivé.
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
      },
    );

    testWidgets('submit button enabled when email valid AND RGPD checked', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(const LoginPage()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'test@exemple.fr');
      await tester.pump();

      // Cocher la case RGPD.
      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('shows MagicLinkSentView when state is linkSent', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
            // Force l'état directement à linkSent pour tester la vue.
            authControllerProvider.overrideWith(
              (ref) => AuthController(ref.read(authRepositoryProvider))
                ..state = const LoginFormState.linkSent(
                  email: 'test@exemple.fr',
                ),
            ),
          ],
          child: const MaterialApp(home: LoginPage()),
        ),
      );
      await tester.pump();

      expect(find.text('Vérifiez votre boîte mail'), findsOneWidget);
      expect(find.text('test@exemple.fr'), findsOneWidget);
    });
  });
}
