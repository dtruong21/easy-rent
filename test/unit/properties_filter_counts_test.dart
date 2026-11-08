import 'package:easyrent/features/properties/application/properties_filter_provider.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_filter.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:flutter_test/flutter_test.dart';

PropertyListItem _item(String id, {String? leaseId}) => PropertyListItem(
  property: Property(
    id: id,
    landlordId: 'l1',
    name: 'Bien $id',
    address: '1 rue X',
    type: PropertyType.appartement,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  activeLeaseId: leaseId,
);

void main() {
  test('propertyMatchesFilter : loués / vacants / tous', () {
    final loue = _item('a', leaseId: 'L1');
    final vacant = _item('b');
    expect(propertyMatchesFilter(loue, PropertyFilter.occupied), isTrue);
    expect(propertyMatchesFilter(vacant, PropertyFilter.occupied), isFalse);
    expect(propertyMatchesFilter(vacant, PropertyFilter.vacant), isTrue);
    expect(propertyMatchesFilter(loue, PropertyFilter.all), isTrue);
  });

  test('propertyFilterCounts compte chaque filtre', () {
    final counts = propertyFilterCounts([
      _item('a', leaseId: 'L1'),
      _item('b'),
      _item('c'),
    ]);
    expect(counts, {
      PropertyFilter.all: 3,
      PropertyFilter.occupied: 1,
      PropertyFilter.vacant: 2,
    });
  });
}
