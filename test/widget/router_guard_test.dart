import 'package:easyrent/core/router/app_router.dart';
import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repo NoOp.
//
// La garde du routeur lit `ref.read(isAuthenticatedProvider)`, ce qu'on
// override directement dans le ProviderScope ; le repo n'a donc qu'à
// satisfaire le contrat AuthRepository sans logique utile.
//
// Note : la migration Firebase a supprimé le concept de "session
// passwordRecovery" (Supabase). Firebase utilise un oobCode lu dans
// l'URL — la garde routeur n'a plus à le gérer (voir
// ResetPasswordPage qui consomme `Uri.base.queryParameters['oobCode']`).
// ---------------------------------------------------------------------------

class _NoOpRepo implements AuthRepository {
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

Widget _buildApp({required bool isAuthenticated, String? initialLocation}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(_NoOpRepo()),
      isAuthenticatedProvider.overrideWithValue(isAuthenticated),
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
    testWidgets('utilisateur non authentifié sur / est redirigé vers /login', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(isAuthenticated: false));
      await tester.pumpAndSettle();

      expect(find.text('Baillan.'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('utilisateur non authentifié tentant /login reste sur /login', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(isAuthenticated: false, initialLocation: '/login'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baillan.'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets(
      'utilisateur authentifié naviguant vers /login est redirigé vers /',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(isAuthenticated: true, initialLocation: '/login'),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsNothing);
        expect(find.text('Baillan.'), findsWidgets);
      },
    );

    testWidgets('/privacy est accessible sans authentification', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(isAuthenticated: false, initialLocation: '/privacy'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Politique de confidentialité'), findsWidgets);
    });

    testWidgets('/privacy est accessible avec authentification', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(isAuthenticated: true, initialLocation: '/privacy'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Politique de confidentialité'), findsWidgets);
    });
  });
}
