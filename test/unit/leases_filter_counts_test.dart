import 'package:easyrent/features/leases/application/leases_filter_provider.dart';
import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_filter.dart';
import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:flutter_test/flutter_test.dart';

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
  bool isLate = false,
}) => LeaseListItem(
  lease: _makeLease(id: id, status: status, endDate: endDate),
  propertyName: propertyName,
  tenantDisplayName: tenantName,
  isLate: isLate,
);

void main() {
  final now = DateTime(2026, 9, 29);

  // Bail actif à jour : pas de date de fin proche, pas en retard.
  final actif = _makeItem(id: 'la', endDate: DateTime(2027, 1, 1));

  // Bail actif en retard de paiement.
  final retard = _makeItem(
    id: 'lr',
    endDate: DateTime(2027, 1, 1),
    isLate: true,
  );

  // Bail actif renouvelable : endDate dans moins de 60 jours (fenêtre
  // `kLeaseRenewalWindowDays`, cf. `isLeaseRenewable`), pas en retard.
  final renouvelable = _makeItem(
    id: 'lw',
    endDate: now.add(const Duration(days: 30)),
  );

  // Bail terminé.
  final termine = _makeItem(id: 'lt', status: LeaseStatus.terminated);

  test('leaseMatchesFilter : active exclut late et renewable', () {
    expect(leaseMatchesFilter(actif, LeaseFilter.active, now), isTrue);
    expect(leaseMatchesFilter(retard, LeaseFilter.active, now), isFalse);
    expect(leaseMatchesFilter(renouvelable, LeaseFilter.active, now), isFalse);
  });

  test('leaseMatchesFilter : renewable exclut late', () {
    expect(
      leaseMatchesFilter(renouvelable, LeaseFilter.renewable, now),
      isTrue,
    );
    expect(leaseMatchesFilter(retard, LeaseFilter.renewable, now), isFalse);
  });

  test('leaseMatchesFilter : late', () {
    expect(leaseMatchesFilter(retard, LeaseFilter.late, now), isTrue);
    expect(leaseMatchesFilter(actif, LeaseFilter.late, now), isFalse);
  });

  test('leaseMatchesFilter : terminated', () {
    expect(leaseMatchesFilter(termine, LeaseFilter.terminated, now), isTrue);
    expect(leaseMatchesFilter(actif, LeaseFilter.terminated, now), isFalse);
  });

  test('leaseMatchesFilter : all toujours vrai', () {
    for (final item in [actif, retard, renouvelable, termine]) {
      expect(leaseMatchesFilter(item, LeaseFilter.all, now), isTrue);
    }
  });

  test('leaseFilterCounts : priorité late > renewable > active', () {
    final counts = leaseFilterCounts([
      actif,
      retard,
      renouvelable,
      termine,
    ], now);
    expect(counts, {
      LeaseFilter.all: 4,
      LeaseFilter.active: 1,
      LeaseFilter.renewable: 1,
      LeaseFilter.late: 1,
      LeaseFilter.terminated: 1,
    });
  });
}
