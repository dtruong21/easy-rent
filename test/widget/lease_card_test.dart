import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/leases/domain/charge_mode.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/leases/presentation/widgets/lease_card.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Lease _makeLease({
  String id = 'L1',
  LeaseStatus status = LeaseStatus.active,
  DateTime? endDate,
  LeaseType leaseType = LeaseType.unfurnished,
  ChargeMode? chargeMode,
}) => Lease(
  id: id,
  landlordId: 'owner',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 75000,
  chargesAmountCents: 5000,
  startDate: DateTime(2024, 1, 1),
  endDate: endDate,
  status: status,
  leaseType: leaseType,
  chargeMode: chargeMode,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

LeaseListItem _item({
  String id = 'L1',
  String propertyName = 'Appartement Lyon',
  String tenantName = 'Marie Martin',
  LeaseStatus status = LeaseStatus.active,
  DateTime? endDate,
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
);

Widget _app(LeaseListItem item) => MaterialApp.router(
  theme: AppTheme.light,
  locale: const Locale('fr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: supportedLocales,
  routerConfig: GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: LeaseCard(item: item, onTap: () {}),
        ),
      ),
      GoRoute(
        path: '/leases/:id',
        builder: (_, s) => Text('lease ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/leases/:id/payments/new',
        builder: (_, s) => Text('payment ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/leases/:id/receipts',
        builder: (_, s) => Text('receipts ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/leases/:id/edit',
        builder: (_, s) => Text('edit ${s.pathParameters['id']}'),
      ),
    ],
  ),
);

void main() {
  testWidgets('chiffre clé loyer CC + libellé "CC / mois"', (t) async {
    await t.pumpWidget(_app(_item()));
    await t.pumpAndSettle();

    expect(find.textContaining('800,00'), findsOneWidget);
    expect(find.text('CC / mois'), findsOneWidget);
  });

  testWidgets('tap action rapide "+ Paiement" → page paiement', (t) async {
    await t.pumpWidget(_app(_item(id: 'L1')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('card_add_payment_L1')));
    await t.pumpAndSettle();

    expect(find.text('payment L1'), findsOneWidget);
  });

  testWidgets('menu ⋮ → Quittances → page quittances', (t) async {
    await t.pumpWidget(_app(_item(id: 'L1')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('lease_menu_L1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('card_receipts_L1')));
    await t.pumpAndSettle();

    expect(find.text('receipts L1'), findsOneWidget);
  });

  testWidgets(
    'bail canRegularizeCharges == false → item "Régulariser les charges" absent',
    (t) async {
      // Bail meublé en forfait : `canRegularizeCharges` == false
      // (cf. `Lease.canRegularizeCharges` / `effectiveChargeMode`).
      await t.pumpWidget(
        _app(
          _item(
            id: 'L1',
            leaseType: LeaseType.furnished,
            chargeMode: ChargeMode.forfait,
          ),
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('lease_menu_L1')));
      await t.pumpAndSettle();

      expect(
        find.byKey(const Key('menu_item_regularize_charges')),
        findsNothing,
      );
    },
  );

  testWidgets('menu ⋮ → Modifier → page édition', (t) async {
    await t.pumpWidget(_app(_item(id: 'L1')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('lease_menu_L1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('card_edit_lease_L1')));
    await t.pumpAndSettle();

    expect(find.text('edit L1'), findsOneWidget);
  });
}
