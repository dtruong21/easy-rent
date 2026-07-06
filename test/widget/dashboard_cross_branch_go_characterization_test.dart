/// Test de RÉGRESSION F-1 (correctif navigation, ex test de caractérisation
/// du bug) — prouve empiriquement que [RecentActivitySection] /
/// [OnboardingFirstSteps] naviguent désormais avec `context.push(...)` (et
/// non plus `context.go(...)`) depuis la branche Accueil vers une SOUS-PAGE
/// PROFONDE d'une autre branche (contrairement au drill-down KPI, qui vise
/// la RACINE `/leases?filter=…` avec `go()` volontairement — déjà couvert
/// par `shell_branch_state_test.dart`).
///
/// AVANT (bug) : `go()` cross-branche remplaçait la pile → un seul `pop()`
/// laissait l'utilisateur dans la branche Baux, jamais de retour vers
/// l'onglet Accueil sans re-taper explicitement dessus.
/// APRÈS (ce test) : `push()` empile la sous-page PAR-DESSUS le shell, qui
/// reste monté avec l'onglet Accueil actif dessous → un seul `pop()` natif
/// restitue le dashboard complet.
///
/// Exerce le VRAI [appRouterProvider] + [StatefulShellRoute.indexedStack]
/// (fakes minimaux, un seul bail "lease-shell-1").
library;

import 'package:easyrent/core/router/app_router.dart';
import 'package:easyrent/core/theme/app_theme.dart';
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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fakes — copie minimale du harnais de shell_branch_state_test.dart.
// ---------------------------------------------------------------------------

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

/// Dashboard non-onboarding avec 1 item d'activité "paiement enregistré" sur
/// le bail fake `lease-shell-1` — reproduit exactement le tuile tappée par
/// l'utilisateur dans `recent_activity_section.dart`.
class _FakeDashboardRepoWithActivity implements DashboardRepository {
  const _FakeDashboardRepoWithActivity();

  @override
  Future<LoyersMoisKpi> fetchLoyersMois() async =>
      const LoyersMoisKpi(encaissedCents: 80000, dueCents: 80000);

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
  Future<List<ActivityItem>> fetchRecentActivity({int limit = 5}) async => [
    ActivityItem.paymentRecorded(
      paymentId: 'payment-shell-1',
      leaseId: 'lease-shell-1',
      tenantName: 'Jean Dupont',
      amountCents: 80000,
      occurredAt: DateTime(2026, 6, 30),
    ),
  ];

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

class _FakeLeaseRepo implements LeaseRepository {
  @override
  Future<List<LeaseListItem>> listForDisplay() async => [
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
          const _FakeDashboardRepoWithActivity(),
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
// Tests de régression F-1
// ---------------------------------------------------------------------------

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RÉGRESSION F-1 — RecentActivitySection.push() cross-branche depuis '
      'Accueil (Accueil → Baux)', () {
    testWidgets(
      'tap "Paiement enregistré" sur Accueil empile la sous-page Baux '
      'PAR-DESSUS le shell (Accueil reste actif dessous) : 1 seul back '
      'restitue le dashboard complet',
      (tester) async {
        // Viewport large — le dashboard ListView contient plusieurs sections
        // (KPI, graphique, rendement, activité) : la taille de test par
        // défaut (800×600) laisse la tuile "Activité récente" hors écran.
        tester.view.physicalSize = const Size(1024, 3600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = await _pumpShellApp(
          tester,
          sessionState: SessionState.fullyAuthenticated,
          initialLocation: '/dashboard',
        );

        expect(_loc(router), '/dashboard');
        expect(find.text('Accueil'), findsWidgets);

        // Reproduit le tap réel de la tuile "Activité récente". Le viewport
        // (1024×3600) est volontairement surdimensionné pour que la card
        // "Activité récente" (en bas du ListView du dashboard) soit déjà
        // dans le viewport sans avoir besoin de scroller.
        final tile = find.textContaining('Paiement enregistré');
        expect(
          tile,
          findsOneWidget,
          reason:
              'La tuile activité doit être visible sur le dashboard '
              'fake (1 item, pas de scroll nécessaire)',
        );
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile, warnIfMissed: false);
        await tester.pumpAndSettle();

        // push() (pas go()) : la configuration du router racine — celle qui
        // pilote la branche affichée par le StatefulShellRoute — NE CHANGE
        // PAS. Le shell reste monté avec Accueil actif ; la sous-page cible
        // est empilée PAR-DESSUS lui dans le Navigator racine.
        expect(
          _loc(router),
          '/dashboard',
          reason:
              'push() empile la sous-page sans reconstruire la '
              'configuration du shell — Accueil reste la branche active.',
        );

        // Le shell (NavigationRail au viewport 1024px large) est bien
        // toujours monté SOUS la sous-page poussée.
        expect(find.byKey(const Key('adaptive_nav_rail')), findsOneWidget);

        // La sous-page ciblée par le tap est bien affichée par-dessus.
        expect(find.text('Modifier le paiement'), findsOneWidget);

        // Un seul retour (BackButton natif) dépile la sous-page — Accueil
        // redevient directement visible, SANS re-taper explicitement dessus.
        final backButton = find.byKey(const Key('app_bar_back'));
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
        await tester.pumpAndSettle();

        expect(
          find.text('Activité récente'),
          findsOneWidget,
          reason:
              'RÉGRESSION F-1 : après le fix (push au lieu de go), un seul '
              'back depuis une tuile Accueil restitue le dashboard complet — '
              "l'utilisateur n'est plus piégé dans la branche Baux.",
        );
        expect(find.text('Modifier le paiement'), findsNothing);
      },
    );
  });
}
