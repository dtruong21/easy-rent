import 'package:easyrent/core/ui/theme/app_colors.dart';
import 'package:easyrent/core/ui/theme/app_radii.dart';
import 'package:easyrent/features/leases/domain/charge_mode.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/leases/presentation/widgets/lease_card.dart';
import 'package:easyrent/features/leases/presentation/widgets/leases_card_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Thème avec extensions Baillan. (AppColors + AppRadii).
ThemeData _appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  extensions: const [AppColors.light, AppRadii()],
);

Lease _makeLease({
  String id = 'l1',
  LeaseStatus status = LeaseStatus.active,
  DateTime? endDate,
  LeaseType leaseType = LeaseType.unfurnished,
  ChargeMode? chargeMode,
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
  leaseType: leaseType,
  chargeMode: chargeMode,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

LeaseListItem _makeItem({
  String id = 'l1',
  String propertyName = 'Appartement Lyon',
  String tenantName = 'Marie Martin',
  LeaseStatus status = LeaseStatus.active,
  DateTime? endDate,
  bool isLate = false,
  LeaseType leaseType = LeaseType.unfurnished,
  ChargeMode? chargeMode,
}) => LeaseListItem(
  lease: _makeLease(
    id: id,
    status: status,
    endDate: endDate,
    leaseType: leaseType,
    chargeMode: chargeMode,
  ),
  propertyName: propertyName,
  tenantDisplayName: tenantName,
  isLate: isLate,
);

/// Capture la dernière URI naviguée (query params inclus) — utilisé pour
/// vérifier le raccourci "Régulariser les charges" (`?action=regularize`).
final List<String> _navigatedUris = [];

Widget _buildCardView(List<LeaseListItem> items) {
  _navigatedUris.clear();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(body: LeasesCardView(leases: items)),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, state) {
          _navigatedUris.add(state.uri.toString());
          return Scaffold(body: Text('detail ${state.pathParameters['id']}'));
        },
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

    testWidgets('bail en retard (isLate=true) → pill "En retard" visible '
        '(FEAT-028)', (tester) async {
      final lateItem = _makeItem(
        id: 'll',
        propertyName: 'Bien En Retard',
        isLate: true,
      );

      await tester.pumpWidget(_buildCardView([lateItem]));
      await tester.pumpAndSettle();

      expect(find.text('En retard'), findsOneWidget);
    });

    testWidgets(
      'bail en retard ET renouvelable → pill "En retard" prime sur "À '
      'renouveler" (FEAT-028, priorité late > renewable)',
      (tester) async {
        final item = _makeItem(
          id: 'llr',
          propertyName: 'Bien Retard Et Renouvelable',
          endDate: DateTime.now().add(const Duration(days: 30)),
          isLate: true,
        );

        await tester.pumpWidget(_buildCardView([item]));
        await tester.pumpAndSettle();

        expect(find.text('En retard'), findsOneWidget);
        expect(find.text('À renouveler'), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Raccourci "Régulariser les charges" (FEAT-030)
  // ---------------------------------------------------------------------------
  group('LeaseCard — menu "Régulariser les charges"', () {
    testWidgets('bail nu — menu overflow visible', (tester) async {
      final item = _makeItem(id: 'ln', leaseType: LeaseType.unfurnished);

      await tester.pumpWidget(_buildCardView([item]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lease_menu_ln')), findsOneWidget);
    });

    testWidgets(
      'bail meublé en provisions (chargeMode absent → défaut FEAT-042) — '
      'menu overflow visible',
      (tester) async {
        final item = _makeItem(id: 'lf', leaseType: LeaseType.furnished);

        await tester.pumpWidget(_buildCardView([item]));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('lease_menu_lf')), findsOneWidget);
      },
    );

    testWidgets('bail meublé en forfait — menu overflow ABSENT', (
      tester,
    ) async {
      final item = _makeItem(
        id: 'lf2',
        leaseType: LeaseType.furnished,
        chargeMode: ChargeMode.forfait,
      );

      await tester.pumpWidget(_buildCardView([item]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lease_menu_lf2')), findsNothing);
    });

    testWidgets('bail mobilité — menu overflow ABSENT (forfait forcé)', (
      tester,
    ) async {
      final item = _makeItem(id: 'lm', leaseType: LeaseType.mobility);

      await tester.pumpWidget(_buildCardView([item]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lease_menu_lm')), findsNothing);
    });

    testWidgets(
      'bail étudiant en provisions (chargeMode absent → défaut FEAT-042) — '
      'menu overflow visible',
      (tester) async {
        final item = _makeItem(id: 'ls', leaseType: LeaseType.student);

        await tester.pumpWidget(_buildCardView([item]));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('lease_menu_ls')), findsOneWidget);
      },
    );

    testWidgets('bail étudiant en forfait — menu overflow ABSENT', (
      tester,
    ) async {
      final item = _makeItem(
        id: 'ls2',
        leaseType: LeaseType.student,
        chargeMode: ChargeMode.forfait,
      );

      await tester.pumpWidget(_buildCardView([item]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lease_menu_ls2')), findsNothing);
    });

    testWidgets(
      'tap "Régulariser les charges" → navigue vers /leases/:id?action=regularize '
      '(sans déclencher le tap de la carte parente)',
      (tester) async {
        final item = _makeItem(
          id: 'lease-reg',
          propertyName: 'Bien Régularisation',
          leaseType: LeaseType.unfurnished,
        );

        await tester.pumpWidget(_buildCardView([item]));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('lease_menu_lease-reg')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('menu_item_regularize_charges')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('menu_item_regularize_charges')));
        await tester.pumpAndSettle();

        expect(find.text('detail lease-reg'), findsOneWidget);
        expect(_navigatedUris, contains('/leases/lease-reg?action=regularize'));
      },
    );
  });
}
