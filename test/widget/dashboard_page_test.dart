/// Tests widget pour [DashboardPage].
library;

import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/domain/onboarding_progress.dart';
import 'package:easyrent/features/dashboard/presentation/dashboard_page.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/action_items_panel.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/shortcuts_row.dart';
import 'package:easyrent/features/leases/application/leases_list_provider.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:easyrent/features/pwa/application/install_prompt_controller.dart';
import 'package:easyrent/features/pwa/data/install_prompt_storage.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
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
  Future<DocsPendingKpi> fetchDocsPending() async =>
      const DocsPendingKpi(count: 0);

  @override
  Future<List<MonthlyCollectedRent>> fetchLastMonthsCollectedRent(
    int months,
  ) async => [];

  @override
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async => [];

  @override
  Future<OnboardingProgress> fetchOnboardingProgress() async => onboarding
      ? const OnboardingProgress(
          hasProperty: false,
          hasTenant: false,
          hasLease: false,
          hasPayment: false,
          hasReceipt: false,
          firstLeaseId: null,
        )
      : const OnboardingProgress(
          hasProperty: true,
          hasTenant: true,
          hasLease: true,
          hasPayment: true,
          hasReceipt: true,
          firstLeaseId: null,
        );
}

class _FakeAuthRepo implements AuthRepository {
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

class _FakeInstallController extends InstallPromptController {
  _FakeInstallController() : super(InstallPromptStorage());
}

/// Fake pour [leasesListProvider] — [ActionItemsPanel] (câblé à la place de
/// `MonthlyCashflowChart`, cf. Task 6) le `ref.watch` en interne. Liste vide
/// par défaut : ces tests ne portent pas sur le panneau d'action lui-même
/// (déjà couvert par `action_items_panel_test.dart`).
class _FakeLeasesNotifier extends LeasesListNotifier {
  @override
  Future<List<LeaseListItem>> build() async => const <LeaseListItem>[];
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
      leasesListProvider.overrideWith(() => _FakeLeasesNotifier()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(extensions: const [AppColors.light]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('fr'),
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
    testWidgets('affiche 2 KPI patrimoniaux (occupation, patrimoine)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kpi_occupation')), findsOneWidget);
      expect(find.byKey(const Key('kpi_patrimoine')), findsOneWidget);
      expect(find.byKey(const Key('kpi_docs')), findsNothing);
      // Les compteurs redondants avec le panneau ont été retirés.
      expect(find.byKey(const Key('kpi_loyers')), findsNothing);
      expect(find.byKey(const Key('kpi_retards')), findsNothing);
      expect(find.byKey(const Key('kpi_renouvellements')), findsNothing);
    });

    testWidgets('affiche le header "Bonjour"', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.textContaining('Bonjour'), findsOneWidget);
    });

    testWidgets(
      'affiche le panneau actionnable à la place du graphe cash-flow',
      (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        expect(find.byType(ActionItemsPanel), findsOneWidget);
      },
    );

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

    testWidgets(
      '3 zones nommées, dans l\'ordre À traiter → patrimoine → analyse',
      (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        final todo = find.text('À traiter');
        final patrimony = find.text('Mon patrimoine');
        final analysis = find.text('Analyse');
        expect(todo, findsOneWidget);
        expect(patrimony, findsOneWidget);
        expect(analysis, findsOneWidget);

        // Ordre vertical : À traiter au-dessus de Mon patrimoine, au-dessus d'Analyse.
        expect(
          tester.getTopLeft(todo).dy,
          lessThan(tester.getTopLeft(patrimony).dy),
        );
        expect(
          tester.getTopLeft(patrimony).dy,
          lessThan(tester.getTopLeft(analysis).dy),
        );
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
    testWidgets('cash flow chart vide affiche texte CardEmptyState', (
      tester,
    ) async {
      // Le repo retourne [] pour fetchLastMonthsCollectedRent → isEmpty = true.
      // Le graphe est désormais replié par défaut (CollapsibleCashflowSection,
      // Task 5/6) : il faut déplier la carte avant que le chart (et donc son
      // empty state) ne soit construit.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      final tile = find.text('Cash-flow mensuel — détail');
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.text("Pas encore d'historique"), findsOneWidget);
      expect(
        find.text(
          'Le cash-flow apparaîtra ici dès le premier loyer encaissé ou la '
          'première dépense enregistrée.',
        ),
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
}
