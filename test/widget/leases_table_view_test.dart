import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/presentation/widgets/leases_table_view.dart';
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

Lease _makeLease({
  String id = 'l1',
  LeaseStatus status = LeaseStatus.active,
  int rentAmountCents = 80000,
  int chargesAmountCents = 5000,
  DateTime? startDate,
  DateTime? endDate,
}) => Lease(
  id: id,
  landlordId: 'owner',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: rentAmountCents,
  chargesAmountCents: chargesAmountCents,
  startDate: startDate ?? DateTime(2024, 1, 1),
  endDate: endDate,
  status: status,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

LeaseListItem _makeItem({
  String id = 'l1',
  String propertyName = 'Appartement Lyon',
  String tenantName = 'Marie Martin',
  LeaseStatus status = LeaseStatus.active,
  int rentAmountCents = 80000,
  int chargesAmountCents = 5000,
  DateTime? startDate,
  DateTime? endDate,
}) => LeaseListItem(
  lease: _makeLease(
    id: id,
    status: status,
    rentAmountCents: rentAmountCents,
    chargesAmountCents: chargesAmountCents,
    startDate: startDate,
    endDate: endDate,
  ),
  propertyName: propertyName,
  tenantDisplayName: tenantName,
);

Widget _buildTableView(List<LeaseListItem> items) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(body: LeasesTableView(leases: items)),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/leases/:id/receipts',
        builder: (context, _) => const Scaffold(body: Text('quittances')),
      ),
      GoRoute(
        path: '/leases/:id/payments/new',
        builder: (context, _) => const Scaffold(body: Text('nouveau paiement')),
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
  group('LeasesTableView', () {
    testWidgets('N lignes — affiche N DataRow', (tester) async {
      final items = [
        _makeItem(id: 'l1', propertyName: 'Bien A'),
        _makeItem(id: 'l2', propertyName: 'Bien B'),
        _makeItem(id: 'l3', propertyName: 'Bien C'),
      ];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.text('Bien A'), findsOneWidget);
      expect(find.text('Bien B'), findsOneWidget);
      expect(find.text('Bien C'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('tri — les deux éléments visibles après clic sur en-tête', (
      tester,
    ) async {
      final items = [
        _makeItem(id: 'l1', propertyName: 'Zebra'),
        _makeItem(id: 'l2', propertyName: 'Alpha'),
      ];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      // Les deux items sont visibles (tri initial ASC par "Bien")
      expect(find.text('Zebra'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);

      // Clic sur l'en-tête "Bien" → déclenche tri
      await tester.tap(find.text('Bien'));
      await tester.pumpAndSettle();

      // Les deux items sont toujours visibles après tri
      expect(find.text('Zebra'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('tap ligne → navigue vers /leases/:id', (tester) async {
      final items = [_makeItem(id: 'lease-tbl', propertyName: 'Bien Nav')];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bien Nav'));
      await tester.pumpAndSettle();

      expect(find.text('detail lease-tbl'), findsOneWidget);
    });

    testWidgets('icônes actions quittances + paiement visibles', (
      tester,
    ) async {
      final items = [_makeItem(id: 'la')];

      await tester.pumpWidget(_buildTableView(items));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('table_receipts_la')), findsOneWidget);
      expect(find.byKey(const Key('table_payment_la')), findsOneWidget);
    });

    testWidgets('état loading — affiche aucun DataRow de données', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(body: LeasesTableView.loading()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
        ),
      );
      await tester.pump();

      // Pas de DataTable de données (squelette affiché)
      expect(find.byType(DataTable), findsNothing);
    });
  });
}
