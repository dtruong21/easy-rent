import 'package:easyrent/features/auth/application/signup_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/signup_page_state.dart';
import 'package:easyrent/features/auth/presentation/signup_page.dart';
import 'package:flutter/gestures.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// Fake repo
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
// Helper
// ---------------------------------------------------------------------------

Widget _buildSignupPage({
  required _FakeAuthRepository repo,
  SignupPageState? initialState,
}) {
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
            const Scaffold(body: Text('Page politique de confidentialité')),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const Scaffold(body: Text('Page CGU')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      if (initialState != null)
        signupControllerProvider.overrideWith(
          (ref) =>
              SignupController(ref.read(authRepositoryProvider))
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SignupPage', () {
    testWidgets('affiche 4 champs de saisie', (tester) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('affiche la case à cocher RGPD', (tester) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
    });

    testWidgets('bouton désactivé par défaut', (tester) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('affiche CircularProgressIndicator en état submitting', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSignupPage(
          repo: _FakeAuthRepository(),
          initialState: const SignupPageState.submitting(),
        ),
      );
      await tester.pump();

      // Seul le bouton dont la requête est en cours affiche le spinner ;
      // sans clic préalable, `_googleClickedLast` est false donc c'est le
      // FilledButton "Créer mon compte" qui spin. L'autre bouton est
      // désactivé mais ne spin pas.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'état awaitingConfirmation affiche SignupConfirmationSentView',
      (tester) async {
        await tester.pumpWidget(
          _buildSignupPage(
            repo: _FakeAuthRepository(),
            initialState: const SignupPageState.awaitingConfirmation(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Vérifiez votre boîte mail'), findsOneWidget);
        expect(find.text('Retour à la connexion'), findsOneWidget);
      },
    );

    testWidgets('bouton "Retour à la connexion" navigue vers /login', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSignupPage(
          repo: _FakeAuthRepository(),
          initialState: const SignupPageState.awaitingConfirmation(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retour à la connexion'));
      await tester.pumpAndSettle();

      expect(find.text('Page connexion'), findsOneWidget);
    });

    testWidgets("affiche le message d'erreur en état error", (tester) async {
      await tester.pumpWidget(
        _buildSignupPage(
          repo: _FakeAuthRepository(),
          initialState: const SignupPageState.error(
            message: 'Un compte existe déjà avec cet email.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Un compte existe déjà'), findsOneWidget);
    });

    testWidgets('lien "J\'ai déjà un compte" navigue vers /login', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      // Le bouton peut être en-dessous du viewport — on fait défiler.
      await tester.ensureVisible(find.text("J'ai déjà un compte"));
      await tester.tap(find.text("J'ai déjà un compte"));
      await tester.pumpAndSettle();

      expect(find.text('Page connexion'), findsOneWidget);
    });

    testWidgets('lien CGU de la case de consentement → navigue vers /terms', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      _tapSpan(tester, "conditions générales d'utilisation");
      await tester.pumpAndSettle();

      expect(find.text('Page CGU'), findsOneWidget);
    });

    testWidgets(
      'lien confidentialité de la case de consentement → navigue vers '
      '/privacy',
      (tester) async {
        await tester.pumpWidget(_buildSignupPage(repo: _FakeAuthRepository()));
        await tester.pumpAndSettle();

        _tapSpan(tester, 'politique de confidentialité');
        await tester.pumpAndSettle();

        expect(find.text('Page politique de confidentialité'), findsOneWidget);
      },
    );
  });
}

/// Déclenche le recognizer du [TextSpan] dont le texte contient [needle].
///
/// Les liens d'un [RichText] ne sont pas des widgets : ils sont
/// inatteignables par `tester.tap(find...)`, on invoque donc leur
/// [TapGestureRecognizer] directement.
void _tapSpan(WidgetTester tester, String needle) {
  final richTexts = tester.widgetList<RichText>(find.byType(RichText));
  for (final richText in richTexts) {
    var fired = false;
    richText.text.visitChildren((span) {
      if (span is TextSpan &&
          (span.text ?? '').contains(needle) &&
          span.recognizer is TapGestureRecognizer) {
        (span.recognizer! as TapGestureRecognizer).onTap?.call();
        fired = true;
        return false;
      }
      return true;
    });
    if (fired) return;
  }
  fail('Aucun TextSpan cliquable contenant « $needle »');
}
