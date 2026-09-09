/// Tests du refresh DYNAMIQUE du routeur sur événement d'auth (BAILLAN-M1).
///
/// Complète `router_three_state_guard_test.dart` (matrice STATIQUE : le
/// sessionState est fixé par override) en testant le flux réel : un
/// événement émis sur `authStateChanges` PENDANT que l'app tourne doit
/// déclencher la réévaluation de la garde et rediriger.
///
/// Régression visée (2026-07-02) : signup/login Google réussi → la popup se
/// ferme, le compte est créé, mais l'app reste plantée sur /signup ou
/// /login (« rien ne se passe »).
library;

import 'dart:async';

import 'package:easyrent/core/router/app_router.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:easyrent/features/pwa/application/install_prompt_controller.dart';
import 'package:easyrent/features/pwa/data/install_prompt_storage.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Repo auth piloté par un [StreamController] — permet de simuler un
/// sign-in/sign-out À CHAUD (pendant que l'app tourne), contrairement aux
/// overrides statiques de sessionStateProvider.
class _StreamAuthRepo implements AuthRepository {
  @override
  Future<String?> reauthenticateWithOAuthProvider(String providerId) async =>
      null;

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {}

  @override
  Future<void> deleteAccount() async {}

  final controller = StreamController<User?>.broadcast();
  User? current;

  @override
  Stream<User?> get authStateChanges => controller.stream;

  @override
  User? get currentUser => current;

  /// Émet un événement d'auth comme le ferait Firebase après un
  /// signInWithPopup/signOut réussi.
  void emit(User? user) {
    current = user;
    controller.add(user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _fakeProfile = LandlordProfile(
  id: 'uid-1',
  email: 'qa@example.com',
  fullName: 'QA Refresh',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  rgpdConsentAt: DateTime(2026),
  rgpdConsentVersion: 'v1-2026-06',
);

class _FakeProfileRepo implements ProfileRepository {
  @override
  Future<LandlordProfile> getCurrent() async => _fakeProfile;

  @override
  Future<LandlordProfile> update({
    String? fullName,
    String? phone,
    String? address,
  }) async => _fakeProfile;
}

class _FakeDashboardRepo implements DashboardRepository {
  const _FakeDashboardRepo();

  @override
  Future<LoyersMoisKpi> fetchLoyersMois() async =>
      const LoyersMoisKpi(encaissedCents: 0, dueCents: 0);

  @override
  Future<RetardsKpi> fetchRetards() async => const RetardsKpi(count: 0);

  @override
  Future<DocsPendingKpi> fetchDocsPending() async =>
      const DocsPendingKpi(count: 0);

  @override
  Future<List<MonthlyCollectedRent>> fetchLastMonthsCollectedRent(
    int months,
  ) async => [];

  @override
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async => [];

  @override
  Future<bool> isLandlordOnboarding() async => false;
}

class _FakeInstallController extends InstallPromptController {
  _FakeInstallController() : super(InstallPromptStorage());
}

// ---------------------------------------------------------------------------
// Harnais
// ---------------------------------------------------------------------------

/// Pump l'app avec le VRAI appRouterProvider (pas de sessionState fixé : la
/// chaîne authStateChangesProvider → sessionStateProvider tourne sur le
/// stream du [repo]). Retourne le routeur capturé.
Future<GoRouter> _pumpApp(WidgetTester tester, _StreamAuthRepo repo) async {
  late final GoRouter router;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        dashboardRepositoryProvider.overrideWithValue(
          const _FakeDashboardRepo(),
        ),
        profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
        installPromptControllerProvider.overrideWith(
          (_) => _FakeInstallController(),
        ),
        installPromptStorageProvider.overrideWith(
          (_) => InstallPromptStorage(),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          router = ref.watch(appRouterProvider);
          return MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            locale: const Locale('fr'),
            supportedLocales: supportedLocales,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _loc(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

MockUser _verifiedUser() => MockUser(
  isAnonymous: false,
  isEmailVerified: true,
  uid: 'uid-refresh-1',
  email: 'qa@example.com',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Router — refresh dynamique sur événement auth', () {
    testWidgets('sign-in à chaud sur /login → redirect /dashboard', (
      tester,
    ) async {
      final repo = _StreamAuthRepo();
      final router = await _pumpApp(tester, repo);

      router.go('/login');
      await tester.pumpAndSettle();
      expect(_loc(router), '/login');

      // Simule la fin d'un signInWithPopup réussi (Google/Apple/password) :
      // Firebase émet le user sur authStateChanges.
      repo.emit(_verifiedUser());
      await tester.pumpAndSettle();

      expect(
        _loc(router),
        '/dashboard',
        reason:
            'Un sign-in à chaud doit déclencher la garde (refreshListenable) '
            'et rediriger hors de /login — régression « popup Google se '
            'ferme et rien ne se passe »',
      );
    });

    testWidgets('sign-in à chaud sur /signup → redirect /dashboard', (
      tester,
    ) async {
      final repo = _StreamAuthRepo();
      final router = await _pumpApp(tester, repo);

      router.go('/signup');
      await tester.pumpAndSettle();
      expect(_loc(router), '/signup');

      repo.emit(_verifiedUser());
      await tester.pumpAndSettle();

      expect(_loc(router), '/dashboard');
    });

    testWidgets(
      'login refusé (rollback new-user-on-login) : sign-in puis sign-out '
      '→ retour /login',
      (tester) async {
        final repo = _StreamAuthRepo();
        final router = await _pumpApp(tester, repo);

        router.go('/login');
        await tester.pumpAndSettle();

        // signInWithGoogle/Apple d'un compte provider SANS compte Baillan :
        // le popup signe l'utilisateur (événement 1), le repo détecte
        // isNewUser et rollback delete()+signOut() (événement 2, ~centaines
        // de ms plus tard). Entre les deux, la garde redirige légitimement
        // vers /dashboard (état fullyAuthenticated transitoire) — l'app
        // DOIT revenir sur /login une fois le rollback terminé, où le
        // message d'erreur du controller est affiché.
        repo.emit(_verifiedUser());
        await tester.pump();
        repo.emit(null);
        await tester.pumpAndSettle();

        expect(
          _loc(router),
          '/login',
          reason:
              'Après le rollback new-user-on-login, la garde doit ramener '
              'sur /login (le flash /dashboard intermédiaire est transitoire)',
        );
      },
    );

    testWidgets('sign-out à chaud sur /dashboard → redirect /login', (
      tester,
    ) async {
      final repo = _StreamAuthRepo();
      // Session déjà active au boot.
      repo.current = _verifiedUser();
      final router = await _pumpApp(tester, repo);

      router.go('/dashboard');
      await tester.pumpAndSettle();
      expect(_loc(router), '/dashboard');

      // Simule le signOut (bouton Déconnexion du dashboard).
      repo.emit(null);
      await tester.pumpAndSettle();

      expect(
        _loc(router),
        '/login',
        reason:
            'Un sign-out à chaud doit déclencher la garde et sortir des '
            'routes protégées',
      );
    });
  });
}
