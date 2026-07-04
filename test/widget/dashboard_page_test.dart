/// Tests widget pour [DashboardPage].
library;

import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/domain/monthly_amount.dart';
import 'package:easyrent/features/dashboard/presentation/dashboard_page.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/kpi_card.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/shortcuts_row.dart';
import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:easyrent/features/pwa/application/install_prompt_controller.dart';
import 'package:easyrent/features/pwa/data/install_prompt_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// Fake repos
// ---------------------------------------------------------------------------

final _fakeProfile = LandlordProfile(
  id: 'uid-1',
  email: 'test@test.com',
  fullName: 'Jean Test',
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
  final bool onboarding;
  final int retards;

  const _FakeDashboardRepo({this.onboarding = false, this.retards = 0});

  @override
  Future<LoyersMoisKpi> fetchLoyersMois() async =>
      const LoyersMoisKpi(encaissedCents: 85000, dueCents: 90000);

  @override
  Future<RetardsKpi> fetchRetards() async => RetardsKpi(count: retards);

  @override
  Future<RenouvellementsKpi> fetchRenouvellements() async =>
      const RenouvellementsKpi(count: 0);

  @override
  Future<DocsPendingKpi> fetchDocsPending() async =>
      const DocsPendingKpi(count: 0);

  @override
  Future<List<MonthlyAmount>> fetchLastMonthsAmounts(int months) async => [];

  @override
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async => [];

  @override
  Future<bool> isLandlordOnboarding() async => onboarding;
}

class _FakeAuthRepo implements AuthRepository {
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

class _FakeInstallController extends InstallPromptController {
  _FakeInstallController() : super(InstallPromptStorage());
}

// ---------------------------------------------------------------------------
// Helper de rendu
// ---------------------------------------------------------------------------

Widget _wrap({bool onboarding = false, int retards = 0}) {
  // FEAT-026 : dans l'app réelle, DashboardPage vit dans la branche Accueil
  // du shell adaptatif ; /leases est une AUTRE branche. Ce mock router ne
  // simule pas le shell (pas nécessaire pour ces tests, qui exercent
  // DashboardPage seule) — le drill-down KPI reste un `go()` classique, dont
  // la sémantique (changer de branche via une URL) est couverte au niveau
  // shell par `shell_branch_state_test.dart`.
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
      GoRoute(
        path: '/simulator',
        builder: (context, state) => const Scaffold(body: Text('simulator')),
      ),
      GoRoute(
        path: '/leases',
        builder: (context, state) => Scaffold(
          body: Text(
            'baux filter=${state.uri.queryParameters['filter'] ?? 'none'}',
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWithValue(
        _FakeDashboardRepo(onboarding: onboarding, retards: retards),
      ),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
      installPromptControllerProvider.overrideWith(
        (_) => _FakeInstallController(),
      ),
      authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
      installPromptStorageProvider.overrideWith((_) => InstallPromptStorage()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(extensions: const [AppColors.light]),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DashboardPage — chargement initial', () {
    testWidgets('affiche d\'abord un CircularProgressIndicator', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      // Avant pumpAndSettle, on est en état loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('DashboardPage — état onboarding', () {
    testWidgets('affiche OnboardingFirstSteps si tout est vide', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(onboarding: true));
      await tester.pumpAndSettle();
      expect(find.text('Bienvenue ! Premiers pas'), findsOneWidget);
    });
  });

  group('DashboardPage — état data normal', () {
    testWidgets('affiche les 4 KPI cards', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kpi_loyers')), findsOneWidget);
      expect(find.byKey(const Key('kpi_retards')), findsOneWidget);
      expect(find.byKey(const Key('kpi_renouvellements')), findsOneWidget);
      expect(find.byKey(const Key('kpi_docs')), findsOneWidget);
    });

    testWidgets('affiche le header "Bonjour"', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.textContaining('Bonjour'), findsOneWidget);
    });

    testWidgets(
      'mobile : affiche ShortcutsRow réduite au seul CTA simulateur (FEAT-026)',
      (tester) async {
        // Viewport mobile (<600px, cf. core/ui/breakpoints.dart) — ShortcutsRow
        // n'est montée que sur ce breakpoint (polish dashboard, cf. 2).
        tester.view.physicalSize = const Size(400, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        expect(find.byType(ShortcutsRow), findsOneWidget);
        expect(find.byKey(const Key('shortcut_simulator')), findsOneWidget);
        // Biens/Locataires/Baux sont désormais des destinations du shell —
        // plus de raccourcis redondants sur l'onglet Accueil.
        expect(find.byKey(const Key('shortcut_properties')), findsNothing);
        expect(find.byKey(const Key('shortcut_tenants')), findsNothing);
        expect(find.byKey(const Key('shortcut_leases')), findsNothing);
      },
    );

    testWidgets(
      'desktop : masque ShortcutsRow (simulateur déjà épinglé au rail, FEAT-026)',
      (tester) async {
        // Viewport desktop (≥600px) — le simulateur est déjà accessible via
        // le rail de navigation, ShortcutsRow serait redondante.
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        expect(find.byType(ShortcutsRow), findsNothing);
      },
    );
  });

  group('DashboardPage — AppBar', () {
    testWidgets('affiche "Accueil" dans l\'AppBar (FEAT-026)', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Accueil'), findsOneWidget);
    });

    testWidgets('ne montre plus les icônes profil/déconnexion (portées par '
        "l'onglet Profil du shell, FEAT-026)", (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.person_outline), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
    });
  });

  group('DashboardPage — empty states (CardEmptyState)', () {
    testWidgets('barchart vide affiche texte CardEmptyState', (tester) async {
      // Le repo retourne [] pour fetchLastMonthsAmounts → isEmpty = true.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text("Pas encore d'historique"), findsOneWidget);
      expect(
        find.text('Les loyers apparaîtront ici dès le 1er paiement.'),
        findsOneWidget,
      );
    });

    testWidgets('activité vide affiche texte CardEmptyState', (tester) async {
      // Le repo retourne [] pour fetchRecentActivity → items empty.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Aucune activité récente'), findsOneWidget);
      expect(
        find.text('Commencez par enregistrer un paiement.'),
        findsOneWidget,
      );
    });
  });

  group('DashboardPage — couleurs sémantiques KpiGrid', () {
    testWidgets('KPI retards utilise AppColors.danger quand count > 0', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(retards: 2));
      await tester.pumpAndSettle();

      // Trouve le KpiCard retards et vérifie sa semanticColor.
      final kpiRetards = tester.widget<KpiCard>(
        find.byKey(const Key('kpi_retards')),
      );
      expect(kpiRetards.semanticColor, equals(AppColors.light.danger.solid));
    });

    testWidgets('KPI retards utilise AppColors.neutral quand count = 0', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final kpiRetards = tester.widget<KpiCard>(
        find.byKey(const Key('kpi_retards')),
      );
      expect(kpiRetards.semanticColor, equals(AppColors.light.neutral.solid));
    });
  });
  group('DashboardPage — drill-down KPI cliquables', () {
    testWidgets('tap « Loyers du mois » → /leases?filter=active', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('kpi_loyers')));
      await tester.pumpAndSettle();

      expect(find.text('baux filter=active'), findsOneWidget);
    });

    testWidgets('tap « Retards » → /leases?filter=late', (tester) async {
      await tester.pumpWidget(_wrap(retards: 2));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('kpi_retards')));
      await tester.pumpAndSettle();

      expect(find.text('baux filter=late'), findsOneWidget);
    });

    testWidgets('tap « Baux à renouveler » → /leases?filter=renewable', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('kpi_renouvellements')));
      await tester.pumpAndSettle();

      expect(find.text('baux filter=renewable'), findsOneWidget);
    });

    testWidgets('« Documents en attente » n\'est PAS cliquable (pas de '
        'page globale documents)', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('kpi_docs')));
      await tester.pumpAndSettle();

      // Toujours sur le dashboard : le tap n'a navigué nulle part.
      expect(find.byKey(const Key('kpi_docs')), findsOneWidget);
      expect(find.textContaining('baux filter='), findsNothing);
    });
  });
}
