import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/widgets/property_card.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

PropertyListItem _item({String? leaseId}) => PropertyListItem(
  property: Property(
    id: 'p1',
    landlordId: 'l1',
    name: 'Studio Test',
    address: '12 rue des Lilas',
    type: PropertyType.appartement,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  activeLeaseId: leaseId,
  currentTenantName: leaseId == null ? null : 'Marie Locataire',
  currentRentCcCents: leaseId == null ? null : 80000,
);

Widget _app(PropertyListItem item) => MaterialApp.router(
  theme: AppTheme.light,
  locale: const Locale('fr'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: supportedLocales,
  routerConfig: GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: PropertyCard(item: item, onTap: () {}),
        ),
      ),
      GoRoute(path: '/leases/new', builder: (_, _) => const Text('new lease')),
      GoRoute(
        path: '/leases/:id',
        builder: (_, s) => Text('lease ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/properties/:id/edit',
        builder: (_, _) => const Text('edit'),
      ),
    ],
  ),
);

void main() {
  testWidgets('loué : loyer en chiffre clé, pas d\'action rapide', (t) async {
    await t.pumpWidget(_app(_item(leaseId: 'L1')));
    await t.pumpAndSettle();
    expect(find.text('Marie Locataire'), findsOneWidget);
    expect(find.textContaining('800,00'), findsOneWidget);
    expect(find.text('CC / mois'), findsOneWidget);
    expect(find.byKey(const Key('card_create_lease_p1')), findsNothing);
  });

  testWidgets('loué : menu ⋮ → Voir le bail', (t) async {
    await t.pumpWidget(_app(_item(leaseId: 'L1')));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('card_view_lease_p1')));
    await t.pumpAndSettle();
    expect(find.text('lease L1'), findsOneWidget);
  });

  testWidgets('vacant : action rapide Créer un bail', (t) async {
    await t.pumpWidget(_app(_item()));
    await t.pumpAndSettle();
    expect(find.text('Aucun locataire'), findsOneWidget);
    await t.tap(find.byKey(const Key('card_create_lease_p1')));
    await t.pumpAndSettle();
    expect(find.text('new lease'), findsOneWidget);
  });
}
