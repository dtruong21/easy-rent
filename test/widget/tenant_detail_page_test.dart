import 'package:easyrent/features/tenants/data/tenant_repository.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/presentation/tenant_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeRepo implements TenantRepository {
  final Tenant? tenant;
  final bool notFound;
  final List<Map<String, dynamic>> leases;
  final int activeLeaseCount;

  const _FakeRepo({
    this.tenant,
    this.notFound = false,
    this.leases = const [],
    this.activeLeaseCount = 0,
  });

  @override
  Future<List<Tenant>> list() async => tenant == null ? [] : [tenant!];

  @override
  Future<Tenant> getById(String id) async {
    if (notFound || tenant == null) throw TenantNotFoundException(id);
    return tenant!;
  }

  @override
  Future<Tenant> create({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
  }) async => throw UnimplementedError();

  @override
  Future<Tenant> update(Tenant t) async => t;

  @override
  Future<int> countActiveLeases(String tenantId) async => activeLeaseCount;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<List<Map<String, dynamic>>> listLeasesForTenant(
    String tenantId,
  ) async => leases;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Tenant _makeTenant({
  String id = 'tenant-1',
  String firstName = 'Jean',
  String lastName = 'Dupont',
  String email = 'jean.dupont@test.com',
  String? phone,
}) => Tenant(
  id: id,
  landlordId: 'owner-1',
  firstName: firstName,
  lastName: lastName,
  email: email,
  phone: phone,
  createdAt: DateTime(2024, 1, 15),
  updatedAt: DateTime(2024, 3, 20),
);

Widget _buildDetailPage({required String tenantId, required _FakeRepo repo}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => TenantDetailPage(id: tenantId),
      ),
      GoRoute(
        path: '/tenants',
        builder: (context, _) => const Scaffold(body: Text('liste locataires')),
      ),
      GoRoute(
        path: '/tenants/:id/edit',
        builder: (_, state) =>
            Scaffold(body: Text('edit ${state.pathParameters['id']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [tenantRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TenantDetailPage', () {
    // -----------------------------------------------------------------------
    // Affichage des champs
    // -----------------------------------------------------------------------
    testWidgets('affiche le prénom et le nom du locataire', (tester) async {
      final tenant = _makeTenant(firstName: 'Marie', lastName: 'Martin');
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Marie'), findsWidgets);
      expect(find.textContaining('Martin'), findsWidgets);
    });

    testWidgets('affiche l\'email du locataire', (tester) async {
      final tenant = _makeTenant(email: 'marie.martin@test.com');
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('marie.martin@test.com'), findsOneWidget);
    });

    testWidgets('affiche le téléphone si présent', (tester) async {
      final tenant = _makeTenant(phone: '06 12 34 56 78');
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('06 12 34 56 78'), findsOneWidget);
    });

    testWidgets('n\'affiche pas la ligne téléphone si phone est null', (
      tester,
    ) async {
      final tenant = _makeTenant(phone: null);
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Téléphone'), findsNothing);
    });

    testWidgets('affiche les dates en format DD/MM/YYYY', (tester) async {
      final tenant = _makeTenant();
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant),
        ),
      );
      await tester.pumpAndSettle();

      // createdAt = DateTime(2024, 1, 15) → "15/01/2024"
      expect(find.text('15/01/2024'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Boutons d'action
    // -----------------------------------------------------------------------
    testWidgets('bouton "Modifier" présent', (tester) async {
      final tenant = _makeTenant();
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_edit_tenant')), findsOneWidget);
    });

    testWidgets('bouton "Archiver ce locataire" présent', (tester) async {
      final tenant = _makeTenant();
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_archive_tenant')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Section baux liés
    // -----------------------------------------------------------------------
    testWidgets('section "Baux liés" présente', (tester) async {
      final tenant = _makeTenant();
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baux liés'), findsOneWidget);
    });

    testWidgets(
      'sans bail — affiche "Aucun bail enregistré pour ce locataire"',
      (tester) async {
        final tenant = _makeTenant();
        await tester.pumpWidget(
          _buildDetailPage(
            tenantId: tenant.id,
            repo: _FakeRepo(tenant: tenant, leases: []),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Aucun bail enregistré'), findsOneWidget);
      },
    );

    testWidgets('avec bail actif — affiche badge "Actif"', (tester) async {
      final tenant = _makeTenant();
      final leases = [
        {
          'id': 'lease-1',
          'property_id': 'prop-1',
          'start_date': '2024-01-01',
          'end_date': null,
          'status': 'active',
          'rent_amount_cents': 75000,
        },
      ];
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant, leases: leases),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Actif'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Cross-user / "Locataire introuvable" (RLS 0 ligne)
    // -----------------------------------------------------------------------
    testWidgets('cross-user — affiche "Locataire introuvable"', (tester) async {
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: 'other-tenant-id',
          repo: const _FakeRepo(notFound: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Locataire introuvable'), findsOneWidget);
    });

    testWidgets(
      'cross-user — page introuvable affiche bouton "Retour à la liste"',
      (tester) async {
        await tester.pumpWidget(
          _buildDetailPage(
            tenantId: 'other-tenant-id',
            repo: const _FakeRepo(notFound: true),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Retour'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // Dialog d'archivage — ouverture
    // -----------------------------------------------------------------------
    testWidgets('tap "Archiver" ouvre le dialog de confirmation', (
      tester,
    ) async {
      final tenant = _makeTenant();
      await tester.pumpWidget(
        _buildDetailPage(
          tenantId: tenant.id,
          repo: _FakeRepo(tenant: tenant, activeLeaseCount: 0),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_archive_tenant')));
      await tester.pumpAndSettle();

      expect(find.text('Archiver ce locataire ?'), findsOneWidget);
      expect(find.text('Archiver'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets(
      'tap "Archiver" avec bail actif — dialog renforcé "bail actif"',
      (tester) async {
        final tenant = _makeTenant();
        await tester.pumpWidget(
          _buildDetailPage(
            tenantId: tenant.id,
            repo: _FakeRepo(tenant: tenant, activeLeaseCount: 1),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_archive_tenant')));
        await tester.pumpAndSettle();

        expect(find.textContaining('bail actif'), findsOneWidget);
      },
    );
  });
}
