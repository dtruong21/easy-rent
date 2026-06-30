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
  Future<List<MonthlyAmount>> fetchLast6MonthsAmounts() async => [];

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

class _FakeInstallController extends InstallPromptController {
  _FakeInstallController() : super(InstallPromptStorage());
}

// ---------------------------------------------------------------------------
// Helper de rendu
// ---------------------------------------------------------------------------

Widget _wrap({bool onboarding = false, int retards = 0}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
      GoRoute(
        path: '/properties/new',
        builder: (context, state) => const Scaffold(body: Text('props')),
      ),
      GoRoute(
        path: '/tenants/new',
        builder: (context, state) => const Scaffold(body: Text('tenants')),
      ),
      GoRoute(
        path: '/leases/new',
        builder: (context, state) => const Scaffold(body: Text('leases')),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const Scaffold(body: Text('profile')),
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

    testWidgets('affiche ShortcutsRow dans le widget tree', (tester) async {
      // Viewport plus grand pour que tout le contenu soit rendu.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsRow), findsOneWidget);
    });
  });

  group('DashboardPage — AppBar', () {
    testWidgets('affiche "Baillan." dans l\'AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Baillan.'), findsOneWidget);
    });
  });

  group('DashboardPage — empty states (CardEmptyState)', () {
    testWidgets('barchart vide affiche texte CardEmptyState', (tester) async {
      // Le repo retourne [] pour fetchLast6MonthsAmounts → isEmpty = true.
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
}
