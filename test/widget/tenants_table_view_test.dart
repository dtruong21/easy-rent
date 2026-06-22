import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenants_table_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Tenant _makeTenant({
  String id = 't1',
  String firstName = 'Jean',
  String lastName = 'Dupont',
  String email = 'jean@test.com',
  String? phone,
}) => Tenant(
  id: id,
  landlordId: 'owner',
  firstName: firstName,
  lastName: lastName,
  email: email,
  phone: phone,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

TenantListItem _makeItem({
  String id = 't1',
  String firstName = 'Jean',
  String lastName = 'Dupont',
  String email = 'jean@test.com',
  String? activeLeaseId,
  String? propertyName,
  int? rentCents,
}) => TenantListItem(
  tenant: _makeTenant(
    id: id,
    firstName: firstName,
    lastName: lastName,
    email: email,
  ),
  activeLeaseId: activeLeaseId,
  currentPropertyName: propertyName,
  activeLeasePeriodLabel: activeLeaseId != null ? 'Depuis 01/01/2024' : null,
  activeLeaseRentCents: rentCents,
);

Widget _buildTableView(List<TenantListItem> items) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: SingleChildScrollView(child: TenantsTableView(tenants: items)),
        ),
      ),
      GoRoute(
        path: '/tenants/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/tenants/:id/edit',
        builder: (_, state) =>
            Scaffold(body: Text('edit ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('lease ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/new',
        builder: (context, _) => const Scaffold(body: Text('new lease')),
      ),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TenantsTableView', () {
    testWidgets('affiche les colonnes de tête', (tester) async {
      await tester.pumpWidget(_buildTableView([]));
      await tester.pumpAndSettle();

      expect(find.text('Nom'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Téléphone'), findsOneWidget);
      expect(find.text('Statut'), findsOneWidget);
      expect(find.text('Bien occupé'), findsOneWidget);
      expect(find.text('Loyer CC'), findsOneWidget);
      expect(find.text('Actions'), findsOneWidget);
    });

    testWidgets('2 locataires — affiche 2 lignes avec noms', (tester) async {
      final items = [
        _makeItem(id: 't1', firstName: 'Jean', lastName: 'Dupont'),
        _makeItem(id: 't2', firstName: 'Sophie', lastName: 'Martin'),
      ];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.textContaining('Jean Dupont'), findsOneWidget);
      expect(find.textContaining('Sophie Martin'), findsOneWidget);
    });

    testWidgets('locataire sans bail — affiche "Sans bail"', (tester) async {
      final items = [_makeItem(id: 't1')];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.text('Sans bail'), findsOneWidget);
    });

    testWidgets('locataire avec bail — affiche "Actif"', (tester) async {
      final items = [
        _makeItem(
          id: 't1',
          activeLeaseId: 'l1',
          propertyName: 'Appartement Test',
          rentCents: 80000,
        ),
      ];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.text('Actif'), findsOneWidget);
    });

    testWidgets('tap ligne → navigue vers /tenants/:id', (tester) async {
      final items = [
        _makeItem(id: 'tenant-abc', firstName: 'Marc', lastName: 'Test'),
      ];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      // Taper sur la ligne via la première cellule du nom
      await tester.tap(find.textContaining('Marc Test'));
      await tester.pumpAndSettle();

      expect(find.text('detail tenant-abc'), findsOneWidget);
    });

    testWidgets('bouton icône modifier — présent dans la ligne', (
      tester,
    ) async {
      final items = [_makeItem(id: 'tenant-edit')];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      // Le bouton modifier est présent dans la ligne de la table.
      expect(find.byKey(const Key('table_edit_tenant-edit')), findsOneWidget);
    });

    testWidgets('locataire avec bail — bouton "Voir le bail" présent', (
      tester,
    ) async {
      final items = [_makeItem(id: 't1', activeLeaseId: 'lease-001')];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('table_lease_t1')), findsOneWidget);
    });

    testWidgets('locataire sans bail — bouton "Créer un bail" présent', (
      tester,
    ) async {
      final items = [_makeItem(id: 't1')];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('table_new_lease_t1')), findsOneWidget);
    });

    testWidgets('état loading — affiche aucune DataTable', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(body: TenantsTableView.loading()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
        ),
      );
      await tester.pump();

      expect(find.byType(DataTable), findsNothing);
    });
  });
}
