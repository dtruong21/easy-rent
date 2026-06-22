import 'package:easyrent/core/router/app_router.dart';
import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake repos selon l'état souhaité.
// ---------------------------------------------------------------------------

class _UnauthenticatedRepo implements AuthRepository {
  @override
  Stream<AuthState> get authStateChanges =>
      // Émet un état signedOut pour initialiser le StreamProvider.
      Stream.value(AuthState(AuthChangeEvent.signedOut, null));

  @override
  Session? get currentSession => null;

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
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<void> signOut() async {}
}

class _PasswordRecoveryRepo implements AuthRepository {
  final _session = _FakeSession();

  @override
  Stream<AuthState> get authStateChanges =>
      // Émet un event passwordRecovery avec une session temporaire, comme
      // Supabase le fait quand l'utilisateur clique le lien de reset password.
      Stream.value(AuthState(AuthChangeEvent.passwordRecovery, _session));

  @override
  Session? get currentSession => _session;

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
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<void> signOut() async {}
}

class _AuthenticatedRepo implements AuthRepository {
  final _session = _FakeSession();

  @override
  Stream<AuthState> get authStateChanges =>
      Stream.value(AuthState(AuthChangeEvent.signedIn, _session));

  @override
  Session? get currentSession => _session;

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
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<void> signOut() async {}
}

/// Session minimale pour simuler un utilisateur connecté.
class _FakeSession extends Session {
  _FakeSession()
    : super(
        accessToken: 'fake-token',
        tokenType: 'bearer',
        user: const User(
          id: '00000000-0000-0000-0000-000000000001',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
}

// ---------------------------------------------------------------------------
// Helper : construit l'app avec GoRouter injecté et le repo donné.
// ---------------------------------------------------------------------------

Widget _buildApp({
  required AuthRepository repo,
  required bool isAuthenticated,
  bool isInPasswordRecovery = false,
  String? initialLocation,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      // On surcharge isAuthenticatedProvider directement pour un contrôle
      // synchrone du redirect (évite la course avec le StreamProvider).
      isAuthenticatedProvider.overrideWithValue(isAuthenticated),
      isInPasswordRecoveryProvider.overrideWithValue(isInPasswordRecovery),
    ],
    child: Consumer(
      builder: (context, ref, _) {
        final router = ref.watch(appRouterProvider);
        if (initialLocation != null) {
          // Naviguer vers la route cible après le premier frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            router.go(initialLocation);
          });
        }
        return MaterialApp.router(routerConfig: router);
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Garde de route', () {
    // -----------------------------------------------------------------------
    // Non authentifié → redirigé vers /login si route protégée
    // -----------------------------------------------------------------------
    testWidgets('utilisateur non authentifié sur / est redirigé vers /login', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(repo: _UnauthenticatedRepo(), isAuthenticated: false),
      );
      await tester.pumpAndSettle();

      // La LoginPage affiche "EasyRent" et le champ email.
      expect(find.text('EasyRent'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('utilisateur non authentifié tentant /login reste sur /login', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          repo: _UnauthenticatedRepo(),
          isAuthenticated: false,
          initialLocation: '/login',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EasyRent'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    // -----------------------------------------------------------------------
    // Authentifié + /login → redirigé vers /
    // -----------------------------------------------------------------------
    testWidgets(
      'utilisateur authentifié naviguant vers /login est redirigé vers /',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            repo: _AuthenticatedRepo(),
            isAuthenticated: true,
            initialLocation: '/login',
          ),
        );
        await tester.pumpAndSettle();

        // Le dashboard affiche son contenu — pas la LoginPage (pas de TextField).
        expect(find.byType(TextField), findsNothing);
        // Le dashboard affiche "EasyRent" dans l'AppBar — pas la LoginPage.
        expect(find.text('EasyRent'), findsWidgets);
      },
    );

    // -----------------------------------------------------------------------
    // /privacy accessible sans authentification
    // -----------------------------------------------------------------------
    testWidgets('/privacy est accessible sans authentification', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          repo: _UnauthenticatedRepo(),
          isAuthenticated: false,
          initialLocation: '/privacy',
        ),
      );
      await tester.pumpAndSettle();

      // La PrivacyPage affiche son titre.
      expect(find.text('Politique de confidentialité'), findsWidgets);
    });

    // -----------------------------------------------------------------------
    // /privacy accessible avec authentification (pas de redirect vers /)
    // -----------------------------------------------------------------------
    testWidgets('/privacy est accessible avec authentification', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          repo: _AuthenticatedRepo(),
          isAuthenticated: true,
          initialLocation: '/privacy',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Politique de confidentialité'), findsWidgets);
    });

    // -----------------------------------------------------------------------
    // passwordRecovery : session temporaire → forcé vers /reset-password
    //
    // Supabase émet AuthChangeEvent.passwordRecovery avec session != null
    // quand l'utilisateur clique le lien de reset password. Sans garde,
    // isAuthed=true enverrait l'utilisateur vers / sans changer son password.
    // -----------------------------------------------------------------------
    testWidgets(
      'en mode passwordRecovery, naviguer vers /login redirige vers /reset-password',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            repo: _PasswordRecoveryRepo(),
            // isAuthed = true car Supabase émet une session temporaire lors
            // du passwordRecovery — c'est précisément le cas problématique.
            isAuthenticated: true,
            isInPasswordRecovery: true,
            initialLocation: '/login',
          ),
        );
        await tester.pumpAndSettle();

        // La ResetPasswordPage doit être affichée, pas la LoginPage.
        // "Nouveau mot de passe" est le titre de ResetPasswordPage.
        expect(find.text('Nouveau mot de passe'), findsWidgets);
        // La LoginPage ne doit PAS être affichée.
        expect(find.text('Se connecter'), findsNothing);
      },
    );

    testWidgets(
      'en mode passwordRecovery, naviguer vers / redirige vers /reset-password',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            repo: _PasswordRecoveryRepo(),
            isAuthenticated: true,
            isInPasswordRecovery: true,
          ),
        );
        await tester.pumpAndSettle();

        // La ResetPasswordPage doit être affichée, pas le Dashboard.
        expect(find.text('Nouveau mot de passe'), findsWidgets);
      },
    );

    testWidgets(
      'en mode passwordRecovery, /reset-password reste sur /reset-password',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            repo: _PasswordRecoveryRepo(),
            isAuthenticated: true,
            isInPasswordRecovery: true,
            initialLocation: '/reset-password',
          ),
        );
        await tester.pumpAndSettle();

        // Pas de boucle redirect — la page est rendue normalement.
        expect(find.text('Nouveau mot de passe'), findsWidgets);
      },
    );
  });
}
