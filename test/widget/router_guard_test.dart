import 'package:easyrent/core/router/app_router.dart';
import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repo NoOp.
//
// La garde du routeur lit `ref.read(sessionStateProvider)`, ce qu'on
// override directement dans le ProviderScope ; le repo n'a donc qu'à
// satisfaire le contrat AuthRepository sans logique utile.
//
// Note : la migration Firebase a supprimé le concept de "session
// passwordRecovery" (Supabase). Firebase utilise un oobCode lu dans
// l'URL — la garde routeur n'a plus à le gérer (voir
// ResetPasswordPage qui consomme `Uri.base.queryParameters['oobCode']`).
//
// BAILLAN-M1 : `/` est désormais LandingPage (publique) — le dashboard a
// bougé en `/dashboard`. Ces tests couvrent le binaire historique
// unauthenticated/fullyAuthenticated ; la matrice complète 3-états (incluant
// `anonymous`) est couverte par `router_three_state_guard_test.dart`.
// ---------------------------------------------------------------------------

class _NoOpRepo implements AuthRepository {
  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async =>
      null;

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {}

  @override
  Future<void> deleteAccount() async {}

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

Widget _buildApp({
  required SessionState sessionState,
  String? initialLocation,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_NoOpRepo()),
      sessionStateProvider.overrideWithValue(sessionState),
    ],
    child: Consumer(
      builder: (context, ref, _) {
        final router = ref.watch(appRouterProvider);
        if (initialLocation != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            router.go(initialLocation);
          });
        }
        return MaterialApp.router(routerConfig: router);
      },
    ),
  );
}

void main() {
  group('Garde de route', () {
    testWidgets('utilisateur non authentifié sur / voit la landing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(sessionState: SessionState.unauthenticated),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baillan.'), findsOneWidget);
      expect(find.byKey(const Key('landing_cta_signup')), findsOneWidget);
    });

    testWidgets('utilisateur non authentifié tentant /login reste sur /login', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          sessionState: SessionState.unauthenticated,
          initialLocation: '/login',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baillan.'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets(
      'utilisateur authentifié naviguant vers /login est redirigé vers /dashboard',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            sessionState: SessionState.fullyAuthenticated,
            initialLocation: '/login',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);
      },
    );

    testWidgets('/privacy est accessible sans authentification', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          sessionState: SessionState.unauthenticated,
          initialLocation: '/privacy',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Politique de confidentialité'), findsWidgets);
    });

    testWidgets('/privacy est accessible avec authentification', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          sessionState: SessionState.fullyAuthenticated,
          initialLocation: '/privacy',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Politique de confidentialité'), findsWidgets);
    });
  });
}
