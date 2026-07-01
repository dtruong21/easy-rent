import 'package:easyrent/features/auth/application/login_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/login_page_state.dart';
import 'package:easyrent/features/auth/presentation/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  bool signInCalled = false;
  Exception? signInError;

  @override
  Stream<User?> get authStateChanges => const Stream<User?>.empty();

  @override
  User? get currentUser => null;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalled = true;
    if (signInError != null) throw signInError!;
  }

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
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _buildLoginPage({
  required _FakeAuthRepository repo,
  LoginPageState? initialState,
}) {
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
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      if (initialState != null)
        loginControllerProvider.overrideWith(
          (ref) =>
              LoginController(ref.read(authRepositoryProvider))
                ..state = initialState,
        ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LoginPage', () {
    testWidgets('affiche les champs email et mot de passe', (tester) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Adresse email'), findsOneWidget);
      expect(find.text('Mot de passe'), findsOneWidget);
    });

    testWidgets('bouton désactivé si champs vides', (tester) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('bouton désactivé si email invalide', (tester) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'invalid-email');
      await tester.enterText(fields.last, 'Password1');
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('bouton activé quand email valide et mot de passe non vide', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final emailField = find.byType(TextField).first;
      await tester.enterText(emailField, 'user@exemple.fr');
      await tester.pump();

      // Le mot de passe est dans un champ obscur — on trouve le 2e TextField.
      final allFields = find.byType(TextField);
      await tester.enterText(allFields.last, 'Password1');
      await tester.pump();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('affiche CircularProgressIndicator en état submitting', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildLoginPage(
          repo: _FakeAuthRepository(),
          initialState: const LoginPageState.submitting(),
        ),
      );
      await tester.pump();

      // Seul le bouton dont la requête est en cours affiche le spinner ;
      // sans clic prélable, `_googleClickedLast` est false donc c'est le
      // FilledButton email/password qui spin. L'autre bouton est désactivé
      // mais ne spin pas.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets("affiche le message d'erreur en état error", (tester) async {
      await tester.pumpWidget(
        _buildLoginPage(
          repo: _FakeAuthRepository(),
          initialState: const LoginPageState.error(
            message: 'Email ou mot de passe incorrect.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
    });

    testWidgets('lien "Mot de passe oublié ?" navigue vers /forgot-password', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      // Le nouveau design (concept "La Page du Registre") ajoute du chrome
      // au-dessus du form (cartouche + aphorisme + filet) — les liens
      // secondaires en bas peuvent tomber hors du viewport de test 800x600
      // par défaut. ensureVisible scroll la SingleChildScrollView avant tap.
      final finder = find.text('Mot de passe oublié ?');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();

      expect(find.text('Mot de passe oublié'), findsOneWidget);
    });

    testWidgets('lien "Créer un compte" navigue vers /signup', (tester) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final finder = find.text('Créer un compte');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();

      expect(find.text('Page inscription'), findsOneWidget);
    });

    testWidgets('lien privacy visible et navigable', (tester) async {
      await tester.pumpWidget(_buildLoginPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      // Le lien est dans un RichText — on trouve via byWidgetPredicate.
      final privacyRichText = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('Politique de confidentialité'),
      );
      expect(privacyRichText, findsOneWidget);
    });
  });
}
