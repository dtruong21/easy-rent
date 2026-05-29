import 'package:easyrent/features/leases/application/lease_form_controller.dart';
import 'package:easyrent/features/leases/data/lease_repository.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_form_state.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/presentation/lease_form_page.dart';
import 'package:easyrent/features/properties/data/property_repository.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repositories
// ---------------------------------------------------------------------------

class _FakeLeaseRepo implements LeaseRepository {
  Lease? createdLease;
  Lease? updatedLease;
  Exception? createError;
  bool hasActiveLease = false;

  @override
  Future<List<LeaseListItem>> listForDisplay() async => [];

  @override
  Future<Lease> getById(String id) async => throw UnimplementedError();

  @override
  Future<Lease> create({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    if (createError != null) throw createError!;
    createdLease = _buildLease(
      propertyId: propertyId,
      tenantId: tenantId,
      rentAmountCents: rentAmountCents,
      chargesAmountCents: chargesAmountCents,
      startDate: startDate,
      endDate: endDate,
    );
    return createdLease!;
  }

  @override
  Future<Lease> update(Lease lease) async {
    updatedLease = lease;
    return lease;
  }

  @override
  Future<Lease> close(String id, {required DateTime effectiveEndDate}) async =>
      throw UnimplementedError();

  @override
  Future<bool> hasOtherActiveLeaseOnProperty(
    String propertyId, {
    String? excludeLeaseId,
  }) async => hasActiveLease;

  @override
  Future<void> archive(String id) async {}

  Lease _buildLease({
    required String propertyId,
    required String tenantId,
    required int rentAmountCents,
    required int chargesAmountCents,
    required DateTime startDate,
    DateTime? endDate,
  }) => Lease(
    id: 'new-lease-id',
    landlordId: 'owner-1',
    propertyId: propertyId,
    tenantId: tenantId,
    rentAmountCents: rentAmountCents,
    chargesAmountCents: chargesAmountCents,
    startDate: startDate,
    endDate: endDate,
    status: LeaseStatus.active,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

class _FakePropertyRepo implements PropertyRepository {
  final List<Property> properties;
  const _FakePropertyRepo({this.properties = const []});

  @override
  Future<List<Property>> list() async => properties;

  @override
  Future<Property> getById(String id) async => properties.first;

  @override
  Future<Property> create({
    required String name,
    required String address,
    required PropertyType type,
    double? surfaceM2,
  }) async => throw UnimplementedError();

  @override
  Future<Property> update(Property property) async => property;

  @override
  Future<int> countActiveLeases(String propertyId) async => 0;

  @override
  Future<void> archive(String id) async {}
}

class _FakeTenantRepo implements TenantRepository {
  final List<Tenant> tenants;
  const _FakeTenantRepo({this.tenants = const []});

  @override
  Future<List<Tenant>> list() async => tenants;

  @override
  Future<Tenant> getById(String id) async => tenants.first;

  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
  }) async => throw UnimplementedError();

  @override
  Future<Tenant> update(Tenant tenant) async => tenant;

  @override
  Future<int> countActiveLeases(String tenantId) async => 0;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async => [];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Property _makeProperty({String id = 'p1', String name = 'Appartement Test'}) =>
    Property(
      id: id,
      landlordId: 'owner-1',
      name: name,
      address: '1 rue Test',
      type: PropertyType.appartement,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

Tenant _makeTenant({
  String id = 't1',
  String firstName = 'Jean',
  String lastName = 'Dupont',
}) => Tenant(
  id: id,
  landlordId: 'owner-1',
  firstName: firstName,
  lastName: lastName,
  email: 'jean.dupont@test.com',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Lease _makeLease({
  String id = 'lease-1',
  String propertyId = 'p1',
  String tenantId = 't1',
}) => Lease(
  id: id,
  landlordId: 'owner-1',
  propertyId: propertyId,
  tenantId: tenantId,
  rentAmountCents: 85000,
  chargesAmountCents: 5000,
  startDate: DateTime(2024, 1, 1),
  status: LeaseStatus.active,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Widget _buildForm({
  Lease? initial,
  _FakeLeaseRepo? leaseRepo,
  List<Property>? properties,
  List<Tenant>? tenants,
  LeaseFormState? initialState,
}) {
  final fakeLeaseRepo = leaseRepo ?? _FakeLeaseRepo();
  final fakePropertyRepo = _FakePropertyRepo(
    properties: properties ?? [_makeProperty()],
  );
  final fakeTenantRepo = _FakeTenantRepo(tenants: tenants ?? [_makeTenant()]);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => LeaseFormPage(initial: initial),
      ),
      GoRoute(
        path: '/leases',
        builder: (context, _) => const Scaffold(body: Text('liste baux')),
      ),
      GoRoute(
        path: '/properties/new',
        builder: (context, _) => const Scaffold(body: Text('nouveau bien')),
      ),
      GoRoute(
        path: '/tenants/new',
        builder: (context, _) =>
            const Scaffold(body: Text('nouveau locataire')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      leaseRepositoryProvider.overrideWithValue(fakeLeaseRepo),
      propertyRepositoryProvider.overrideWithValue(fakePropertyRepo),
      tenantRepositoryProvider.overrideWithValue(fakeTenantRepo),
      if (initialState != null)
        leaseFormControllerProvider.overrideWith(
          (ref) => LeaseFormController(ref)..state = initialState,
        ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LeaseFormPage', () {
    // -----------------------------------------------------------------------
    // Mode création — champs présents
    // -----------------------------------------------------------------------
    testWidgets('mode création — titre "Nouveau bail"', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Nouveau bail'), findsOneWidget);
    });

    testWidgets('mode création — bouton "Créer le bail" présent', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Créer le bail'), findsOneWidget);
    });

    testWidgets('mode création — champ loyer HC présent', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_rent')), findsOneWidget);
    });

    testWidgets('mode création — champ charges présent', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_charges')), findsOneWidget);
    });

    testWidgets('mode création — champ date de début présent', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_start_date')), findsOneWidget);
    });

    testWidgets('mode création — checkbox CDI présente', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('checkbox_open_ended')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Validation — champs obligatoires vides
    // -----------------------------------------------------------------------
    testWidgets(
      'validation — erreur "Veuillez sélectionner un bien" si soumis sans bien',
      (tester) async {
        await tester.pumpWidget(_buildForm());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_submit_lease_form')));
        await tester.pumpAndSettle();

        expect(find.text('Veuillez sélectionner un bien'), findsOneWidget);
      },
    );

    testWidgets(
      'validation — erreur "Veuillez sélectionner un locataire" si soumis sans locataire',
      (tester) async {
        await tester.pumpWidget(_buildForm());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_submit_lease_form')));
        await tester.pumpAndSettle();

        expect(find.text('Veuillez sélectionner un locataire'), findsOneWidget);
      },
    );

    testWidgets('validation — erreur loyer si loyer vide à la soumission', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_submit_lease_form')));
      await tester.pumpAndSettle();

      expect(find.text('Le loyer est obligatoire'), findsOneWidget);
    });

    testWidgets('validation — erreur date de début si date manquante', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_submit_lease_form')));
      await tester.pumpAndSettle();

      expect(find.text('La date de début est obligatoire'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Validation — montants invalides
    // -----------------------------------------------------------------------
    testWidgets('validation — loyer ≤ 0 → erreur inline', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field_rent')), '-100');
      await tester.tap(find.byKey(const Key('btn_submit_lease_form')));
      await tester.pumpAndSettle();

      expect(
        find.text('Le loyer doit être un montant positif'),
        findsOneWidget,
      );
    });

    testWidgets('validation — charges négatives → erreur inline', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field_charges')), '-50');
      await tester.tap(find.byKey(const Key('btn_submit_lease_form')));
      await tester.pumpAndSettle();

      expect(
        find.text('Les charges ne peuvent pas être négatives'),
        findsOneWidget,
      );
    });

    // -----------------------------------------------------------------------
    // Mode création — liste vide (hint)
    // -----------------------------------------------------------------------
    testWidgets(
      'mode création — aucun bien → affiche hint "Vous devez d\'abord créer un bien"',
      (tester) async {
        await tester.pumpWidget(_buildForm(properties: []));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Vous devez d\'abord créer un bien'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'mode création — aucun locataire → affiche hint "Vous devez d\'abord créer un locataire"',
      (tester) async {
        await tester.pumpWidget(_buildForm(tenants: []));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Vous devez d\'abord créer un locataire'),
          findsOneWidget,
        );
      },
    );

    // -----------------------------------------------------------------------
    // Mode édition — titre et bouton
    // -----------------------------------------------------------------------
    testWidgets('mode édition — titre "Modifier le bail"', (tester) async {
      final lease = _makeLease();
      await tester.pumpWidget(_buildForm(initial: lease));
      await tester.pumpAndSettle();

      expect(find.text('Modifier le bail'), findsOneWidget);
    });

    testWidgets('mode édition — bouton "Enregistrer"', (tester) async {
      final lease = _makeLease();
      await tester.pumpWidget(_buildForm(initial: lease));
      await tester.pumpAndSettle();

      expect(find.text('Enregistrer'), findsOneWidget);
    });

    testWidgets('mode édition — champ loyer pré-rempli', (tester) async {
      final lease = _makeLease(); // rentAmountCents = 85000
      await tester.pumpWidget(_buildForm(initial: lease));
      await tester.pumpAndSettle();

      // 85000 centimes → "850,00"
      expect(find.text('850,00'), findsOneWidget);
    });

    testWidgets('mode édition — champ charges pré-rempli', (tester) async {
      final lease = _makeLease(); // chargesAmountCents = 5000
      await tester.pumpWidget(_buildForm(initial: lease));
      await tester.pumpAndSettle();

      // 5000 centimes → "50,00"
      expect(find.text('50,00'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Toggle CDI
    // -----------------------------------------------------------------------
    testWidgets('checkbox CDI cochée — masque le champ end_date', (
      tester,
    ) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      // Par défaut la checkbox CDI est cochée (end_date null par défaut).
      // Le champ end_date ne devrait pas être visible.
      expect(find.byKey(const Key('field_end_date')), findsNothing);
    });

    testWidgets('décocher CDI → champ end_date visible', (tester) async {
      await tester.pumpWidget(_buildForm());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('checkbox_open_ended')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('field_end_date')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État submitting
    // -----------------------------------------------------------------------
    testWidgets('état submitting — bouton désactivé', (tester) async {
      await tester.pumpWidget(
        _buildForm(initialState: const LeaseFormState.submitting()),
      );
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.byKey(const Key('btn_submit_lease_form')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('état submitting — CircularProgressIndicator visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildForm(initialState: const LeaseFormState.submitting()),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // État erreur — message inline
    // -----------------------------------------------------------------------
    testWidgets('état erreur — message affiché inline', (tester) async {
      await tester.pumpWidget(
        _buildForm(
          initialState: const LeaseFormState.error(
            message: 'Erreur de connexion',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });
  });
}
