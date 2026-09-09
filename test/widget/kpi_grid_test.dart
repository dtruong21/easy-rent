import 'package:easyrent/core/i18n/locale_resolution.dart';
import 'package:easyrent/core/theme/app_theme.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_kpi.dart';
import 'package:easyrent/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:easyrent/features/dashboard/presentation/widgets/kpi_grid.dart';
import 'package:easyrent/features/properties/application/properties_list_provider.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakePropsNotifier extends PropertiesListItemsNotifier {
  _FakePropsNotifier(this._items);
  final List<PropertyListItem> _items;
  @override
  Future<List<PropertyListItem>> build() async => _items;
}

PropertyListItem _prop({String? activeLeaseId, int? price}) => PropertyListItem(
  property: Property(
    id: 'p${activeLeaseId ?? ''}${price ?? ''}',
    landlordId: 'lord1',
    name: 'Bien',
    address: '1 rue',
    type: PropertyType.studio,
    purchasePriceCents: price,
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  ),
  activeLeaseId: activeLeaseId,
);

DashboardSnapshot _snapshot() => const DashboardSnapshot(
  loyers: LoyersMoisKpi(encaissedCents: 0, dueCents: 0),
  retards: RetardsKpi(count: 0),
  renouvellements: RenouvellementsKpi(count: 0),
  docs: DocsPendingKpi(count: 2),
  activity: [],
  isOnboarding: false,
);

Widget _wrap(List<PropertyListItem> items) => ProviderScope(
  overrides: [
    propertiesListItemsProvider.overrideWith(() => _FakePropsNotifier(items)),
  ],
  child: MaterialApp.router(
    theme: AppTheme.light,
    routerConfig: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: KpiGrid(snapshot: _snapshot())),
        ),
        GoRoute(
          path: '/properties',
          builder: (_, _) => const Scaffold(body: Text('properties')),
        ),
      ],
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('fr'),
    supportedLocales: supportedLocales,
  ),
);

void main() {
  testWidgets('affiche occupation, patrimoine, docs — plus les anciens KPI', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        _prop(activeLeaseId: 'l1', price: 11800000),
        _prop(activeLeaseId: null, price: 11800000),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi_occupation')), findsOneWidget);
    expect(find.byKey(const Key('kpi_patrimoine')), findsOneWidget);
    expect(find.byKey(const Key('kpi_docs')), findsOneWidget);
    expect(find.byKey(const Key('kpi_retards')), findsNothing);
    expect(find.byKey(const Key('kpi_renouvellements')), findsNothing);
    expect(find.byKey(const Key('kpi_loyers')), findsNothing);
    expect(find.textContaining('50'), findsWidgets);
    expect(find.textContaining('236'), findsWidgets);
  });

  testWidgets('occupation tap → /properties', (tester) async {
    await tester.pumpWidget(
      _wrap([_prop(activeLeaseId: 'l1', price: 11800000)]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kpi_occupation')));
    await tester.pumpAndSettle();
    expect(find.text('properties'), findsOneWidget);
  });

  testWidgets('aucun bien → occupation « — », patrimoine « — »', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap([]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kpi_occupation')), findsOneWidget);
    expect(find.byKey(const Key('kpi_patrimoine')), findsOneWidget);
  });
}
