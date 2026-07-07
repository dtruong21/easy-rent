/// Tests widget pour [LandingPage] (BAILLAN-M1).
library;

import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/landing/presentation/landing_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async =>
      null;

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {}

  @override
  Future<void> deleteAccount() async {}

  bool signInAnonymouslyCalled = false;
  Exception? signInAnonymouslyError;

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
  Future<void> sendCurrentUserEmailVerification() async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signUpWithGoogle({required bool rgpdConsent}) async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signUpWithApple({required bool rgpdConsent}) async {}

  @override
  Future<void> signInAnonymously() async {
    signInAnonymouslyCalled = true;
    if (signInAnonymouslyError != null) throw signInAnonymouslyError!;
  }

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

  @override
  Future<void> reauthenticateWithPassword(String currentPassword) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}
}

Widget _buildApp(_FakeAuthRepository repo) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LandingPage()),
      GoRoute(
        path: '/simulator',
        builder: (context, state) => const Scaffold(body: Text('Simulateur')),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const Scaffold(body: Text('Signup')),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('Login')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('LandingPage — contenu', () {
    testWidgets('affiche le wordmark et la tagline', (tester) async {
      await tester.pumpWidget(_buildApp(_FakeAuthRepository()));
      await tester.pump();

      expect(find.text('Baillan.'), findsOneWidget);
      expect(
        find.textContaining('Simulez votre prochain investissement locatif'),
        findsOneWidget,
      );
    });

    testWidgets('affiche les 2 CTA et le lien connexion', (tester) async {
      await tester.pumpWidget(_buildApp(_FakeAuthRepository()));
      await tester.pump();

      expect(find.byKey(const Key('landing_cta_anonymous')), findsOneWidget);
      expect(find.byKey(const Key('landing_cta_signup')), findsOneWidget);
      expect(find.byKey(const Key('landing_cta_login')), findsOneWidget);
      expect(find.text('Continuer sans compte'), findsOneWidget);
      expect(find.text('Créer un compte'), findsOneWidget);
      expect(find.text("J'ai déjà un compte"), findsOneWidget);
    });
  });

  group('LandingPage — CTA "Continuer sans compte"', () {
    testWidgets('déclenche signInAnonymously puis navigue vers /simulator', (
      tester,
    ) async {
      final repo = _FakeAuthRepository();
      await tester.pumpWidget(_buildApp(repo));
      await tester.pump();

      await tester.tap(find.byKey(const Key('landing_cta_anonymous')));
      await tester.pumpAndSettle();

      expect(repo.signInAnonymouslyCalled, isTrue);
      expect(find.text('Simulateur'), findsOneWidget);
    });

    testWidgets('affiche un snackbar et reste sur / en cas d\'échec réseau', (
      tester,
    ) async {
      final repo = _FakeAuthRepository()
        ..signInAnonymouslyError = FirebaseAuthException(
          code: 'network-request-failed',
        );
      await tester.pumpWidget(_buildApp(repo));
      await tester.pump();

      await tester.tap(find.byKey(const Key('landing_cta_anonymous')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Connexion impossible, réessayez.'), findsOneWidget);
      expect(find.text('Baillan.'), findsOneWidget);
    });
  });

  group('LandingPage — CTA "Créer un compte" et "J\'ai déjà un compte"', () {
    testWidgets('navigue vers /signup', (tester) async {
      await tester.pumpWidget(_buildApp(_FakeAuthRepository()));
      await tester.pump();

      await tester.tap(find.byKey(const Key('landing_cta_signup')));
      await tester.pumpAndSettle();

      expect(find.text('Signup'), findsOneWidget);
    });

    testWidgets('navigue vers /login', (tester) async {
      await tester.pumpWidget(_buildApp(_FakeAuthRepository()));
      await tester.pump();

      // Le lien vit en bas de la feuille « Page de garde » — hors du
      // viewport de test (600 px) tant qu'on ne scrolle pas jusqu'à lui.
      await tester.ensureVisible(find.byKey(const Key('landing_cta_login')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('landing_cta_login')));
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsOneWidget);
    });
  });
}
