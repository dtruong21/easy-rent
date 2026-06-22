import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/presentation/widgets/lease_card.dart';
import 'package:easyrent/features/leases/presentation/widgets/leases_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Thème avec extensions EasyRent (AppColors + AppRadii).
ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Lease _makeLease({
  String id = 'l1',
  LeaseStatus status = LeaseStatus.active,
  DateTime? endDate,
}) => Lease(
  id: id,
  landlordId: 'owner',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 80000,
  chargesAmountCents: 5000,
  startDate: DateTime(2024, 1, 1),
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
  DateTime? endDate,
}) => LeaseListItem(
  lease: _makeLease(id: id, status: status, endDate: endDate),
  propertyName: propertyName,
  tenantDisplayName: tenantName,
);

Widget _buildCardView(List<LeaseListItem> items) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(body: LeasesCardView(leases: items)),
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
  group('LeasesCardView', () {
    testWidgets('0 item — affiche aucune LeaseCard', (tester) async {
      await tester.pumpWidget(_buildCardView([]));
      await tester.pumpAndSettle();

      expect(find.byType(LeaseCard), findsNothing);
    });

    testWidgets('3 items — affiche 3 LeaseCard', (tester) async {
      final items = [
        _makeItem(id: 'l1', propertyName: 'Bien 1'),
        _makeItem(id: 'l2', propertyName: 'Bien 2'),
        _makeItem(id: 'l3', propertyName: 'Bien 3'),
      ];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.byType(LeaseCard), findsNWidgets(3));
      expect(find.text('Bien 1'), findsOneWidget);
      expect(find.text('Bien 2'), findsOneWidget);
      expect(find.text('Bien 3'), findsOneWidget);
    });

    testWidgets('6 items — affiche 6 LeaseCard', (tester) async {
      final items = List.generate(
        6,
        (i) => _makeItem(id: 'l$i', propertyName: 'Bien $i'),
      );

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      expect(find.byType(LeaseCard), findsNWidgets(6));
    });

    testWidgets('tap card → navigue vers /leases/:id', (tester) async {
      final items = [_makeItem(id: 'lease-xyz', propertyName: 'Bien Test')];

      await tester.pumpWidget(_buildCardView(items));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bien Test'));
      await tester.pumpAndSettle();

      expect(find.text('detail lease-xyz'), findsOneWidget);
    });

    testWidgets('état loading — affiche aucune LeaseCard', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(body: LeasesCardView.loading()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router, theme: _appTheme()),
        ),
      );
      await tester.pump();

      expect(find.byType(LeaseCard), findsNothing);
    });

    testWidgets('bail renouvelable → pill "À renouveler" visible', (
      tester,
    ) async {
      // endDate dans 30 jours (< 60j → renewable)
      final renewableItem = _makeItem(
        id: 'lr',
        propertyName: 'Bien Renouvelable',
        endDate: DateTime.now().add(const Duration(days: 30)),
      );

      await tester.pumpWidget(_buildCardView([renewableItem]));
      await tester.pumpAndSettle();

      expect(find.text('À renouveler'), findsOneWidget);
    });
  });
}
