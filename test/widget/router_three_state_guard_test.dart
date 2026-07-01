/// Matrice exhaustive des gardes de routeur 3-états (BAILLAN-M1).
///
/// Complète `router_guard_test.dart` (historique binaire) avec le nouveau
/// `SessionState.anonymous` et les routes propres à BAILLAN-M1 (landing,
/// dashboard déplacé, simulateur ouvert aux anonymes).
library;

import 'package:easyrent/core/router/app_router.dart';
import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
}

/// Pump l'app routée avec [sessionState] fixé, navigue vers [location] puis
/// retourne l'emplacement matched final résolu par le routeur (après tous
/// les redirects en chaîne).
Future<String> _resolvedLocation(
  WidgetTester tester, {
  required SessionState sessionState,
  required String location,
}) async {
  late final GoRouter capturedRouter;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_NoOpRepo()),
        sessionStateProvider.overrideWithValue(sessionState),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final router = ref.watch(appRouterProvider);
          capturedRouter = router;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            router.go(location);
          });
          return MaterialApp.router(routerConfig: router);
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return capturedRouter.routerDelegate.currentConfiguration.uri.toString();
}

void main() {
  group('Router 3-états — unauthenticated', () {
    testWidgets('/ → landing (pas de redirect)', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.unauthenticated,
        location: '/',
      );
      expect(loc, '/');
    });

    testWidgets('/login → reste accessible', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.unauthenticated,
        location: '/login',
      );
      expect(loc, '/login');
    });

    testWidgets('/simulator → redirect /login', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.unauthenticated,
        location: '/simulator',
      );
      expect(loc, '/login');
    });

    testWidgets('/dashboard → redirect /login', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.unauthenticated,
        location: '/dashboard',
      );
      expect(loc, '/login');
    });

    testWidgets('/properties → redirect /login', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.unauthenticated,
        location: '/properties',
      );
      expect(loc, '/login');
    });
  });

  group('Router 3-états — anonymous', () {
    testWidgets('/ → redirect /simulator', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.anonymous,
        location: '/',
      );
      expect(loc, '/simulator');
    });

    testWidgets('/login → reste accessible (public)', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.anonymous,
        location: '/login',
      );
      expect(loc, '/login');
    });

    testWidgets('/simulator → accessible, pas de redirect', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.anonymous,
        location: '/simulator',
      );
      expect(loc, '/simulator');
    });

    testWidgets('/dashboard → redirect / (landing)', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.anonymous,
        location: '/dashboard',
      );
      expect(loc, '/simulator'); // / redirige elle-même vers /simulator
    });

    testWidgets('/properties → redirect / puis /simulator', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.anonymous,
        location: '/properties',
      );
      expect(loc, '/simulator');
    });

    testWidgets('/privacy → reste accessible (public)', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.anonymous,
        location: '/privacy',
      );
      expect(loc, '/privacy');
    });
  });

  group('Router 3-états — fullyAuthenticated', () {
    testWidgets('/ → redirect /dashboard', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.fullyAuthenticated,
        location: '/',
      );
      expect(loc, '/dashboard');
    });

    testWidgets('/login → redirect /dashboard', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.fullyAuthenticated,
        location: '/login',
      );
      expect(loc, '/dashboard');
    });

    testWidgets('/signup → redirect /dashboard', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.fullyAuthenticated,
        location: '/signup',
      );
      expect(loc, '/dashboard');
    });

    testWidgets('/simulator → accessible', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.fullyAuthenticated,
        location: '/simulator',
      );
      expect(loc, '/simulator');
    });

    testWidgets('/properties → accessible', (tester) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.fullyAuthenticated,
        location: '/properties',
      );
      expect(loc, '/properties');
    });

    testWidgets('/reset-password → reste accessible même connecté', (
      tester,
    ) async {
      final loc = await _resolvedLocation(
        tester,
        sessionState: SessionState.fullyAuthenticated,
        location: '/reset-password',
      );
      expect(loc, '/reset-password');
    });
  });
}
