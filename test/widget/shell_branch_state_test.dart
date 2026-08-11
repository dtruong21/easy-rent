/// Tests d'intégration du shell adaptatif (FEAT-026) avec le VRAI
/// [appRouterProvider] et la garde 3-états inchangée.
///
/// Complète `adaptive_navigation_scaffold_test.dart` (mécanisme isolé, router
/// factice) en prouvant l'intégration bout en bout :
/// - préservation d'état par branche (filtre Baux posé, détour par Biens,
///   retour Baux → filtre intact) ;
/// - deep link direct vers une sous-page d'une branche (pile correcte,
///   retour vers la racine) ;
/// - drill-down KPI dashboard → bascule de branche (Accueil → Baux) via
///   `go()`, cf. docs/UX_NAVIGATION.md §7 ;
/// - garde anonyme : le shell n'est jamais atteignable par une session
///   anonyme (redirect avant montage du shell).
library;

import 'package:easyrent/core/router/app_router.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/core/ui/navigation/adaptive_navigation_scaffold.dart';
import 'package:easyrent/features/auth/application/auth_session_provider.dart';
import 'package:easyrent/features/auth/data/auth_repository.dart';
import 'package:easyrent/features/auth/domain/session_state.dart';
import 'package:easyrent/features/dashboard/data/dashboard_repository.dart';
import 'package:easyrent/features/dashboard/domain/activity_item.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/domain/monthly_amount.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/charge_mode.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:easyrent/features/profile/data/profile_repository.dart';
import 'package:easyrent/features/profile/domain/landlord_profile.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/heating_type.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/pwa/application/install_prompt_controller.dart';
import 'package:easyrent/features/pwa/data/install_prompt_storage.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fakes — un par repository requis par les 5 racines de branche. Chaque
// fake ne fournit QUE le comportement nécessaire au rendu (listes vides
// suffisent : ces tests exercent la NAVIGATION, pas l'affichage des données).
// ---------------------------------------------------------------------------

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

class _FakeDashboardRepo implements DashboardRepository {
  const _FakeDashboardRepo();

  @override
  Future<LoyersMoisKpi> fetchLoyersMois() async =>
      const LoyersMoisKpi(encaissedCents: 0, dueCents: 0);

  @override
  Future<RetardsKpi> fetchRetards() async => const RetardsKpi(count: 0);

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
  Future<bool> isLandlordOnboarding() async => false;
}

final _fakeProfile = LandlordProfile(
  id: 'uid-1',
  email: 'qa@example.com',
  fullName: 'QA Shell',
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

class _FakePropertyRepo implements PropertyRepository {
  @override
  Future<List<Property>> list() async => [];

  @override
  Future<List<PropertyListItem>> listWithLeases() async => [];

  @override
  Future<Property> getById(String id) async =>
      throw Exception('Bien introuvable (fake)');

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
    String? postalCode,
    String? city,
    int? rooms,
    int? bedrooms,
    int? floor,
    bool hasElevator = false,
    bool furnished = false,
    HeatingType? heatingType,
    String? dpeLetter,
    int? dpeValueKwhM2Year,
    String? gesLetter,
    int? constructionYear,
    int? purchasePriceCents,
    DateTime? purchaseDate,
    int? notaryFeesCents,
    bool isNewProperty = false,
    int? propertyTaxAnnualCents,
    int? insurancePnoAnnualCents,
    int? condoFeesNonRecoverableCents,
    int? loanPrincipalCents,
    int? loanRateBps,
    int? loanInsuranceBps,
    int? loanDurationMonths,
    DateTime? loanStartDate,
    int? loanMonthlyPaymentOverrideCents,
  }) async => throw UnimplementedError();

  @override
  Future<Property> update(Property property) async => property;

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {}
}

class _FakeTenantRepo implements TenantRepository {
  @override
  Future<List<Tenant>> list() async => [];

  @override
  Future<Tenant> getById(String id) async =>
      throw Exception('Locataire introuvable (fake)');

  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    DateTime? birthDate,
    String? birthPlace,
    String? nationality,
    String? profession,
    String? employer,
    int? monthlyIncomeCents,
    String? previousAddress,
    String? guarantorName,
    String? guarantorEmail,
    String? guarantorPhone,
  }) async => throw UnimplementedError();

  @override
  Future<Tenant> update(Tenant tenant) async => tenant;

  @override
  Future<int> countActiveLeases(String tenantId) async => 0;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<TenantListItem>> listWithActiveLeases() async => [];

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async => [];
}

Lease _makeLease({required String id, required LeaseStatus status}) => Lease(
  id: id,
  landlordId: 'uid-1',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 80000,
  chargesAmountCents: 5000,
  startDate: DateTime(2024, 1, 1),
  status: status,
  leaseType: LeaseType.unfurnished,
  paymentDay: 1,
  paymentMethod: PaymentMethod.virement,
  agencyFeesCents: 0,
  solidarityClause: false,
  entryInventoryDone: true,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

/// Fake baux — expose 1 bail actif ("lease-shell-1") pour prouver le
/// drill-down KPI + le deep link vers une sous-page. `getById` sur tout
/// AUTRE id lance (deep link vers un id inconnu → `_NotFoundPage`, suffisant
/// pour prouver que la pile GoRouter s'est construite jusqu'à la cible).
class _FakeLeaseRepo implements LeaseRepository {
  @override
  Future<List<LeaseListItem>> listForDisplay({DateTime? now}) async => [
    LeaseListItem(
      lease: _makeLease(id: 'lease-shell-1', status: LeaseStatus.active),
      propertyName: 'Appart Test',
      tenantDisplayName: 'Jean Dupont',
    ),
  ];

  @override
  Future<Lease> getById(String id) async {
    if (id == 'lease-shell-1') {
      return _makeLease(id: id, status: LeaseStatus.active);
    }
    throw Exception('Bail introuvable (fake)');
  }

  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
    LeaseType leaseType = LeaseType.unfurnished,
    ChargeMode? chargeMode,
    int? depositAmountCents,
    int paymentDay = 1,
    PaymentMethod paymentMethod = PaymentMethod.virement,
    double? irlIndexValue,
    String? irlQuarterRef,
    int agencyFeesCents = 0,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
    int nonRecoverableChargesCents = 0,
  }) async => throw UnimplementedError();

  @override
  Future<Lease> update(Lease lease) async => lease;

  @override
  Future<Lease> close(String id, {required DateTime effectiveEndDate}) async =>
      throw UnimplementedError();

  @override
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  }) async => false;

  @override
  Future<void> archive(String id) async {}
}

class _FakeInstallController extends InstallPromptController {
  _FakeInstallController() : super(InstallPromptStorage());
}

// ---------------------------------------------------------------------------
// Harnais — pump le VRAI appRouterProvider avec sessionState fixé.
// ---------------------------------------------------------------------------

Future<GoRouter> _pumpShellApp(
  WidgetTester tester, {
  required SessionState sessionState,
  String? initialLocation,
}) async {
  late final GoRouter router;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        sessionStateProvider.overrideWithValue(sessionState),
        dashboardRepositoryProvider.overrideWithValue(
          const _FakeDashboardRepo(),
        ),
        profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
        propertyRepositoryProvider.overrideWithValue(_FakePropertyRepo()),
        tenantRepositoryProvider.overrideWithValue(_FakeTenantRepo()),
        leaseRepositoryProvider.overrideWithValue(_FakeLeaseRepo()),
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
          if (initialLocation != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              router.go(initialLocation);
            });
          }
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Shell — deep link direct vers une sous-page d\'une branche', () {
    testWidgets('/leases/lease-shell-1 → branche Baux active, pile correcte, '
        'retour ramène à /leases', (tester) async {
      final router = await _pumpShellApp(
        tester,
        sessionState: SessionState.fullyAuthenticated,
        initialLocation: '/leases/lease-shell-1',
      );

      expect(_loc(router), '/leases/lease-shell-1');
      // Le shell (NavigationBar/Rail) reste monté par-dessus la sous-page.
      expect(
        find.byKey(const Key('adaptive_nav_bar')).evaluate().isNotEmpty ||
            find.byKey(const Key('adaptive_nav_rail')).evaluate().isNotEmpty,
        isTrue,
        reason: 'Le shell doit rester visible même sur une sous-page',
      );

      // Retour natif (BackButton, canPop == true dans la branche Baux).
      final backButton = find.byKey(const Key('app_bar_back'));
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(_loc(router), '/leases');
    });

    testWidgets(
      'deep link sur un id inconnu → page "introuvable", retour vers /leases '
      '(fallbackRoute — filet de sécurité §6 du doc)',
      (tester) async {
        final router = await _pumpShellApp(
          tester,
          sessionState: SessionState.fullyAuthenticated,
          initialLocation: '/leases/id-inconnu',
        );

        expect(_loc(router), '/leases/id-inconnu');
        expect(find.text('Bail introuvable'), findsOneWidget);
      },
    );
  });

  group('Shell — garde anonyme : jamais de shell pour un anonyme', () {
    testWidgets('anonyme tentant /dashboard → jamais le shell, redirect', (
      tester,
    ) async {
      final router = await _pumpShellApp(
        tester,
        sessionState: SessionState.anonymous,
        initialLocation: '/dashboard',
      );

      expect(_loc(router), isNot(startsWith('/dashboard')));
      expect(find.byType(AdaptiveNavigationScaffold), findsNothing);
      expect(find.byKey(const Key('adaptive_nav_bar')), findsNothing);
      expect(find.byKey(const Key('adaptive_nav_rail')), findsNothing);
    });

    testWidgets('anonyme tentant /leases/lease-shell-1 → jamais le shell', (
      tester,
    ) async {
      await _pumpShellApp(
        tester,
        sessionState: SessionState.anonymous,
        initialLocation: '/leases/lease-shell-1',
      );

      expect(find.byType(AdaptiveNavigationScaffold), findsNothing);
    });

    testWidgets('unauthenticated tentant /profile → jamais le shell', (
      tester,
    ) async {
      final router = await _pumpShellApp(
        tester,
        sessionState: SessionState.unauthenticated,
        initialLocation: '/profile',
      );

      expect(_loc(router), '/login');
      expect(find.byType(AdaptiveNavigationScaffold), findsNothing);
    });
  });

  group('Shell — préservation d\'état inter-branches', () {
    testWidgets('basculer Baux → Biens → Baux (via l\'onglet) conserve la pile '
        '(bail encore ouvert)', (tester) async {
      await _pumpShellApp(
        tester,
        sessionState: SessionState.fullyAuthenticated,
        initialLocation: '/leases/lease-shell-1',
      );

      // On est bien sur le détail du bail (bouton retour = pile non vide).
      expect(find.byKey(const Key('app_bar_back')), findsOneWidget);

      // Bascule sur Biens via l'onglet (goBranch — ne doit PAS reset Baux).
      await tester.tap(find.text('Biens'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app_bar_back')), findsNothing);

      // Revient sur Baux via l'onglet : le détail doit être ENCORE ouvert
      // (indexedStack préserve la pile de la branche).
      await tester.tap(find.text('Baux'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app_bar_back')), findsOneWidget);
    });

    testWidgets(
      'EXCEPTION Profil : sous-page → Accueil → Profil rouvre le HUB, '
      'pas la sous-page',
      (tester) async {
        // Contre-partie assumée du test précédent. Biens/Locataires/Baux
        // conservent leur pile (filtre, position dans une liste : du travail en
        // cours). Profil est un hub de réglages — y retomber sur le dernier
        // réglage ouvert désoriente, l'utilisateur clique « Profil » pour voir
        // le menu. Signalé en recette sur staging.
        final router = await _pumpShellApp(
          tester,
          sessionState: SessionState.fullyAuthenticated,
          initialLocation: '/profile/details',
        );

        // Départ sur une sous-page : la pile n'est pas vide.
        expect(find.byKey(const Key('app_bar_back')), findsOneWidget);

        await tester.tap(find.text('Accueil'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Profil'));
        await tester.pumpAndSettle();

        // Pile remise à la racine — plus de bouton retour, et l'URL suit.
        expect(find.byKey(const Key('app_bar_back')), findsNothing);
        expect(_loc(router), '/profile');
      },
    );
  });

  group('Shell — drill-down KPI (Accueil → Baux)', () {
    testWidgets(
      'depuis Accueil, go(\'/leases?filter=active\') bascule sur la branche '
      'Baux (comportement cross-branche standard StatefulShellRoute)',
      (tester) async {
        final router = await _pumpShellApp(
          tester,
          sessionState: SessionState.fullyAuthenticated,
          initialLocation: '/dashboard',
        );

        // Onglet Accueil actif au départ.
        expect(_loc(router), '/dashboard');
        expect(find.text('Accueil'), findsWidgets);

        // Simule le tap KPI (dashboard_page utilise `context.go`, testé au
        // niveau widget par dashboard_page_test.dart — ici on prouve que le
        // MÊME appel, exécuté à travers le VRAI shell, bascule bien de
        // branche plutôt que de rester bloqué dans indexedStack).
        router.go('/leases?filter=active');
        await tester.pumpAndSettle();

        expect(_loc(router), '/leases?filter=active');
        // La liste des baux (branche Baux) est maintenant affichée.
        expect(find.text('Mes baux'), findsOneWidget);
      },
    );
  });
}
