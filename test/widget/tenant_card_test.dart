import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenant_card.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Tenant _makeTenant({
  String id = 't1',
  String email = 'jean@test.com',
  String? phone,
}) => Tenant(
  id: id,
  landlordId: 'owner',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: email,
  phone: phone,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

TenantListItem _item({
  String id = 't1',
  String? leaseId,
  String? phone,
  String? propertyName,
}) => TenantListItem(
  tenant: _makeTenant(id: id, phone: phone),
  activeLeaseId: leaseId,
  currentPropertyName: leaseId == null ? null : (propertyName ?? 'Studio Test'),
  activeLeasePeriodLabel: leaseId == null ? null : 'Depuis 01/01/2024',
  activeLeaseRentCents: leaseId == null ? null : 80000,
  activeLeaseChargesCents: leaseId == null ? null : 5000,
);

Widget _app(TenantListItem item) => MaterialApp.router(
  theme: AppTheme.light,
  locale: const Locale('fr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: supportedLocales,
  routerConfig: GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: TenantCard(item: item, onTap: () {}),
        ),
      ),
      GoRoute(path: '/leases/new', builder: (_, _) => const Text('new lease')),
      GoRoute(
        path: '/leases/:id',
        builder: (_, s) => Text('lease ${s.pathParameters['id']}'),
      ),
      GoRoute(path: '/tenants/:id/edit', builder: (_, _) => const Text('edit')),
    ],
  ),
);

void main() {
  testWidgets(
    'avec bail + téléphone : chiffre clé loyer+charges, action rapide '
    'Appeler, pas de bouton email, menu contient Envoyer un email',
    (t) async {
      await t.pumpWidget(_app(_item(leaseId: 'L1', phone: '0612345678')));
      await t.pumpAndSettle();

      expect(find.textContaining('850,00'), findsOneWidget);
      expect(find.text('CC / mois'), findsOneWidget);
      expect(find.byKey(const Key('card_call_t1')), findsOneWidget);
      expect(find.byKey(const Key('card_email_t1')), findsNothing);

      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('menu_email_t1')), findsOneWidget);
    },
  );

  testWidgets(
    'avec bail sans téléphone : action rapide email, menu ne contient '
    'plus Envoyer un email',
    (t) async {
      await t.pumpWidget(_app(_item(leaseId: 'L1')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('card_email_t1')), findsOneWidget);
      expect(find.byKey(const Key('card_call_t1')), findsNothing);

      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('menu_email_t1')), findsNothing);
    },
  );

  testWidgets('avec bail : menu ⋮ → Voir le bail', (t) async {
    await t.pumpWidget(_app(_item(leaseId: 'L1', phone: '0612345678')));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('card_view_lease_t1')));
    await t.pumpAndSettle();

    expect(find.text('lease L1'), findsOneWidget);
  });

  testWidgets(
    'sans bail : action rapide "Créer un bail" → tap navigue vers new lease',
    (t) async {
      await t.pumpWidget(_app(_item()));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('card_create_lease_t1')));
      await t.pumpAndSettle();

      expect(find.text('new lease'), findsOneWidget);
    },
  );

  testWidgets('sans bail : menu ⋮ contient Envoyer un email et Modifier', (
    t,
  ) async {
    await t.pumpWidget(_app(_item()));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('menu_email_t1')), findsOneWidget);
    expect(find.byKey(const Key('card_edit_tenant_t1')), findsOneWidget);
  });
}
