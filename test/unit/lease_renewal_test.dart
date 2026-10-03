import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_renewal.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:flutter_test/flutter_test.dart';

Lease _lease({DateTime? endDate}) => Lease(
  id: 'l1',
  landlordId: 'u1',
  propertyId: 'p1',
  tenantId: 't1',
  rentAmountCents: 80000,
  chargesAmountCents: 0,
  nonRecoverableChargesCents: 0,
  startDate: DateTime(2020, 1, 1),
  endDate: endDate,
  status: LeaseStatus.active,
  createdAt: DateTime(2020, 1, 1),
  updatedAt: DateTime(2020, 1, 1),
);

void main() {
  final now = DateTime(2026, 9, 8);
  test('endDate dans 30j → renewable', () {
    expect(
      isLeaseRenewable(_lease(endDate: now.add(const Duration(days: 30))), now),
      isTrue,
    );
  });
  test('endDate à 60j pile → NON renewable (strict <)', () {
    expect(
      isLeaseRenewable(_lease(endDate: now.add(const Duration(days: 60))), now),
      isFalse,
    );
  });
  test('endDate null → non renewable', () {
    expect(isLeaseRenewable(_lease(endDate: null), now), isFalse);
  });
  test('endDate déjà passée → renewable (parité avec le filtre existant)', () {
    expect(
      isLeaseRenewable(
        _lease(endDate: now.subtract(const Duration(days: 5))),
        now,
      ),
      isTrue,
    );
  });
}
