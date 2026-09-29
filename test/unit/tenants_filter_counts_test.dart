import 'package:easyrent/features/tenants/application/tenants_filter_provider.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_filter.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

TenantListItem _item(String id, {String? leaseId}) => TenantListItem(
  tenant: Tenant(
    id: id,
    landlordId: 'l1',
    firstName: 'Prénom $id',
    lastName: 'Nom $id',
    email: '$id@test.com',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  activeLeaseId: leaseId,
);

void main() {
  test('tenantMatchesFilter : avec bail / sans bail / tous', () {
    final avecBail = _item('a', leaseId: 'L1');
    final sansBail = _item('b');
    expect(tenantMatchesFilter(avecBail, TenantFilter.withActiveLease), isTrue);
    expect(
      tenantMatchesFilter(sansBail, TenantFilter.withActiveLease),
      isFalse,
    );
    expect(
      tenantMatchesFilter(sansBail, TenantFilter.withoutActiveLease),
      isTrue,
    );
    expect(
      tenantMatchesFilter(avecBail, TenantFilter.withoutActiveLease),
      isFalse,
    );
    expect(tenantMatchesFilter(avecBail, TenantFilter.all), isTrue);
    expect(tenantMatchesFilter(sansBail, TenantFilter.all), isTrue);
  });

  test('tenantFilterCounts compte chaque filtre', () {
    final counts = tenantFilterCounts([
      _item('a', leaseId: 'L1'),
      _item('b', leaseId: 'L2'),
      _item('c'),
    ]);
    expect(counts, {
      TenantFilter.all: 3,
      TenantFilter.withActiveLease: 2,
      TenantFilter.withoutActiveLease: 1,
    });
  });
}
