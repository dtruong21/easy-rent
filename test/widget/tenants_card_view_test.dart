import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenant_card.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenants_card_view.dart';
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
}) => Tenant(
  id: id,
  landlordId: 'owner',
  firstName: firstName,
  lastName: lastName,
  email: email,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

TenantListItem _makeItem({
  String id = 't1',
  String firstName = 'Jean',
  String lastName = 'Dupont',
  String? activeLeaseId,
  String? propertyName,
}) => TenantListItem(
  tenant: _makeTenant(id: id, firstName: firstName, lastName: lastName),
  activeLeaseId: activeLeaseId,
  currentPropertyName: propertyName,
  activeLeasePeriodLabel: activeLeaseId != null ? 'Depuis 01/01/2024' : null,
  activeLeaseRentCents: activeLeaseId != null ? 80000 : null,
);

Widget _buildCardView(List<TenantListItem> items) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            Scaffold(body: TenantsCardView(tenants: items)),
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
  group('TenantsCardView', () {
    testWidgets('0 item — affiche aucune TenantCard', (tester) async {
      await tester.pumpWidget(_buildCardView([]));
      await tester.pumpAndSettle();

      expect(find.byType(TenantCard), findsNothing);
    });

    testWidgets('3 items — affiche 3 TenantCard', (tester) async {
      final items = [
        _makeItem(id: 't1', firstName: 'Jean', lastName: 'Dupont'),
        _makeItem(id: 't2', firstName: 'Sophie', lastName: 'Martin'),
        _makeItem(id: 't3', firstName: 'Paul', lastName: 'Durand'),
      ];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.byType(TenantCard), findsNWidgets(3));
      expect(find.textContaining('Jean Dupont'), findsOneWidget);
      expect(find.textContaining('Sophie Martin'), findsOneWidget);
      expect(find.textContaining('Paul Durand'), findsOneWidget);
    });

    testWidgets('6 items — affiche 6 TenantCard', (tester) async {
      final items = List.generate(
        6,
        (i) => _makeItem(id: 't$i', firstName: 'Prénom', lastName: 'Nom$i'),
      );

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.byType(TenantCard), findsNWidgets(6));
    });

    testWidgets('tap card → navigue vers /tenants/:id', (tester) async {
      final items = [
        _makeItem(id: 'tenant-xyz', firstName: 'Jean', lastName: 'Test'),
      ];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('Jean Test'));
      await tester.pumpAndSettle();

      expect(find.text('detail tenant-xyz'), findsOneWidget);
    });

    testWidgets('état loading — affiche aucune TenantCard', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(body: TenantsCardView.loading()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
        ),
      );
      await tester.pump();

      expect(find.byType(TenantCard), findsNothing);
    });

    testWidgets('locataire sans bail → pill "Sans bail" visible', (
      tester,
    ) async {
      final items = [_makeItem(id: 'ts', firstName: 'Lucie', lastName: 'Sans')];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.text('Sans bail'), findsOneWidget);
    });

    testWidgets('locataire avec bail → pill "Actif" visible', (tester) async {
      final items = [
        _makeItem(
          id: 'ta',
          firstName: 'Marc',
          lastName: 'Actif',
          activeLeaseId: 'l1',
          propertyName: 'Appartement Test',
        ),
      ];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.text('Actif'), findsOneWidget);
    });
  });
}
