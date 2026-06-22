import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/application/reset_password_controller.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/reset_password_state.dart';
import 'package:easyrent/features/auth/presentation/reset_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fake repo
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements AuthRepository {
  final Session? session;
  Exception? updateError;

  _FakeAuthRepository({this.session});

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => session;

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
  Future<void> updatePassword(String newPassword) async {
    if (updateError != null) throw updateError!;
  }

  @override
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

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
      // authStateChangesProvider doit émettre l'état correct pour ce test.
      authStateChangesProvider.overrideWith((ref) => repo.authStateChanges),
      if (initialState != null)
        resetPasswordControllerProvider.overrideWith(
          (ref) =>
              ResetPasswordController(ref.read(authRepositoryProvider))
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
  group('ResetPasswordPage', () {
    testWidgets('affiche _InvalidLinkView quand pas de session (stream vide)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildPage(repo: _FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Lien invalide ou expiré'), findsOneWidget);
      expect(find.text('Demander un nouveau lien'), findsOneWidget);
    });

    testWidgets(
      'affiche ResetPasswordForm quand session active (currentSession non null)',
      (tester) async {
        // On simule une session existante via currentSession non null.
        // Le stream vide n'émet rien, donc on se rabat sur currentSession.
        final mockSession = _FakeAuthRepository(session: null);
        // Pour simuler hasRecoverySession = true on surcharge directement
        // authStateChangesProvider en émettant un état avec session.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(mockSession),
              authStateChangesProvider.overrideWith(
                (ref) => Stream.value(
                  AuthState(AuthChangeEvent.passwordRecovery, null),
                ),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: GoRouter(
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
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nouveau mot de passe'), findsAtLeastNWidgets(1));
        expect(find.text('Lien invalide ou expiré'), findsNothing);
      },
    );

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

    testWidgets('affiche CircularProgressIndicator en état submitting', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
            authStateChangesProvider.overrideWith(
              (ref) => Stream.value(
                AuthState(AuthChangeEvent.passwordRecovery, null),
              ),
            ),
            resetPasswordControllerProvider.overrideWith(
              (ref) =>
                  ResetPasswordController(ref.read(authRepositoryProvider))
                    ..state = const ResetPasswordState.submitting(),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
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
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
