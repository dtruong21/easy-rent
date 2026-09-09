import 'package:easyrent/features/dashboard/application/dashboard_portfolio_kpis_provider.dart';
import 'package:easyrent/features/properties/application/properties_list_provider.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePropsNotifier extends PropertiesListItemsNotifier {
  _FakePropsNotifier(this._items);
  final List<PropertyListItem> _items;
  @override
  Future<List<PropertyListItem>> build() async => _items;
}

PropertyListItem _item({
  required String id,
  String? activeLeaseId,
  int? purchasePriceCents,
}) => PropertyListItem(
  property: Property(
    id: id,
    landlordId: 'lord1',
    name: 'Bien $id',
    address: '1 rue',
    type: PropertyType.studio,
    purchasePriceCents: purchasePriceCents,
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  ),
  activeLeaseId: activeLeaseId,
);

void main() {
  ProviderContainer containerWith(List<PropertyListItem> items) =>
      ProviderContainer(
        overrides: [
          propertiesListItemsProvider.overrideWith(
            () => _FakePropsNotifier(items),
          ),
        ],
      );

  test('occupation + patrimoine (2 biens, 1 loué, prix des 2)', () async {
    final c = containerWith([
      _item(id: 'a', activeLeaseId: 'l1', purchasePriceCents: 11800000),
      _item(id: 'b', activeLeaseId: null, purchasePriceCents: 11800000),
    ]);
    addTearDown(c.dispose);
    await c.read(propertiesListItemsProvider.future);
    final k = c.read(dashboardPortfolioKpisProvider).value!;
    expect(k.occupied, 1);
    expect(k.total, 2);
    expect(k.vacant, 1);
    expect(k.occupancyPercent, 50);
    expect(k.patrimoineCents, 23600000);
    expect(k.propertiesWithPrice, 2);
    expect(k.hasProperties, isTrue);
    expect(k.hasAnyPrice, isTrue);
  });

  test('aucun bien → occupancyPercent null, hasProperties false', () async {
    final c = containerWith([]);
    addTearDown(c.dispose);
    await c.read(propertiesListItemsProvider.future);
    final k = c.read(dashboardPortfolioKpisProvider).value!;
    expect(k.total, 0);
    expect(k.occupancyPercent, isNull);
    expect(k.hasProperties, isFalse);
    expect(k.hasAnyPrice, isFalse);
  });

  test('prix partiellement renseignés', () async {
    final c = containerWith([
      _item(id: 'a', activeLeaseId: 'l1', purchasePriceCents: 11800000),
      _item(id: 'b', activeLeaseId: 'l2', purchasePriceCents: null),
    ]);
    addTearDown(c.dispose);
    await c.read(propertiesListItemsProvider.future);
    final k = c.read(dashboardPortfolioKpisProvider).value!;
    expect(k.patrimoineCents, 11800000);
    expect(k.propertiesWithPrice, 1);
    expect(k.occupancyPercent, 100);
  });
}
