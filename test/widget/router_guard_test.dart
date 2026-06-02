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
  Future<void> sendMagicLink(String email) async {}

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
  Future<void> sendMagicLink(String email) async {}

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
  String? initialLocation,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      // On surcharge isAuthenticatedProvider directement pour un contrôle
      // synchrone du redirect (évite la course avec le StreamProvider).
      isAuthenticatedProvider.overrideWithValue(isAuthenticated),
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
      expect(find.byType(TextField), findsOneWidget);
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
      expect(find.byType(TextField), findsOneWidget);
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
  });
}
