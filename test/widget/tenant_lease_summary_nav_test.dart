/// Tests de régression FEAT-005 sur TenantLeaseSummary :
/// - Chaque entrée de bail est maintenant cliquable et navigue vers /leases/:id.
/// - Tests ajoutés sans modifier les assertions existantes dans tenant_lease_summary_test.dart.
library;

import 'package:easyrent/features/tenants/presentation/widgets/tenant_lease_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helper avec router (nécessaire pour context.push)
// ---------------------------------------------------------------------------

Widget _buildWithRouter(List<Map<String, dynamic>> leases) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) =>
            Scaffold(body: TenantLeaseSummary(leases: leases)),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('bail ${state.pathParameters['id']}')),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TenantLeaseSummary — navigation FEAT-005', () {
    testWidgets('bail avec id — affiche le lien "Voir le bail"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWithRouter([
          {
            'id': 'lease-nav-1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voir le bail'), findsOneWidget);
    });

    testWidgets('tap sur un bail navigue vers /leases/:id', (tester) async {
      await tester.pumpWidget(
        _buildWithRouter([
          {
            'id': 'lease-nav-1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
          },
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Voir le bail'));
      await tester.pumpAndSettle();

      expect(find.text('bail lease-nav-1'), findsOneWidget);
    });

    testWidgets('bail avec id vide — pas de lien "Voir le bail"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWithRouter([
          {
            'id': '',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voir le bail'), findsNothing);
    });

    testWidgets('plusieurs baux — chacun affiche un lien "Voir le bail"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWithRouter([
          {
            'id': 'lease-1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
          },
          {
            'id': 'lease-2',
            'property_id': 'p2',
            'start_date': '2023-01-01',
            'end_date': '2024-01-01',
            'status': 'terminated',
            'rent_amount_cents': 65000,
          },
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voir le bail'), findsNWidgets(2));
    });

    testWidgets('tap sur le 2e bail navigue vers son id', (tester) async {
      await tester.pumpWidget(
        _buildWithRouter([
          {
            'id': 'lease-1',
            'property_id': 'p1',
            'start_date': '2024-01-01',
            'end_date': null,
            'status': 'active',
            'rent_amount_cents': 80000,
          },
          {
            'id': 'lease-2',
            'property_id': 'p2',
            'start_date': '2023-01-01',
            'end_date': '2024-01-01',
            'status': 'terminated',
            'rent_amount_cents': 65000,
          },
        ]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Voir le bail').last);
      await tester.pumpAndSettle();

      expect(find.text('bail lease-2'), findsOneWidget);
    });
  });
}
