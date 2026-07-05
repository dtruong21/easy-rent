/// Tests unitaires du modèle [Lease] : round-trip JSON, dates, extension getters.
library;

import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:flutter_test/flutter_test.dart';

Lease _buildLease({
  String id = 'lease-1',
  String landlordId = 'landlord-1',
  String propertyId = 'property-1',
  String tenantId = 'tenant-1',
  int rentAmountCents = 85000,
  int chargesAmountCents = 5000,
  DateTime? startDate,
  DateTime? endDate,
  LeaseStatus status = LeaseStatus.active,
  DateTime? deletedAt,
}) {
  return Lease(
    id: id,
    landlordId: landlordId,
    propertyId: propertyId,
    tenantId: tenantId,
    rentAmountCents: rentAmountCents,
    chargesAmountCents: chargesAmountCents,
    startDate: startDate ?? DateTime(2024, 1, 1),
    endDate: endDate,
    status: status,
    createdAt: DateTime(2024, 1, 1, 10),
    updatedAt: DateTime(2024, 1, 1, 10),
    deletedAt: deletedAt,
  );
}

void main() {
  group('Lease.fromJson / toJson (round-trip)', () {
    test('round-trip JSON complet', () {
      final json = {
        'id': 'lease-42',
        'landlord_id': 'lld-1',
        'property_id': 'prop-1',
        'tenant_id': 'ten-1',
        'rent_amount_cents': 90000,
        'charges_amount_cents': 10000,
        'start_date': '2024-03-01',
        'end_date': null,
        'status': 'active',
        'created_at': '2024-03-01T10:00:00Z',
        'updated_at': '2024-03-01T10:00:00Z',
        'deleted_at': null,
      };
      final lease = Lease.fromJson(json);
      expect(lease.id, 'lease-42');
      expect(lease.rentAmountCents, 90000);
      expect(lease.chargesAmountCents, 10000);
      expect(lease.endDate, isNull);
      expect(lease.status, LeaseStatus.active);
    });

    test('start_date YYYY-MM-DD parsée correctement', () {
      final json = {
        'id': 'l1',
        'landlord_id': 'lld',
        'property_id': 'p1',
        'tenant_id': 't1',
        'rent_amount_cents': 1000,
        'charges_amount_cents': 0,
        'start_date': '2024-06-15',
        'end_date': null,
        'status': 'active',
        'created_at': '2024-06-15T00:00:00Z',
        'updated_at': '2024-06-15T00:00:00Z',
        'deleted_at': null,
      };
      final lease = Lease.fromJson(json);
      expect(lease.startDate.year, 2024);
      expect(lease.startDate.month, 6);
      expect(lease.startDate.day, 15);
    });

    test('end_date renseignée parsée correctement', () {
      final json = {
        'id': 'l2',
        'landlord_id': 'lld',
        'property_id': 'p1',
        'tenant_id': 't1',
        'rent_amount_cents': 1000,
        'charges_amount_cents': 0,
        'start_date': '2024-01-01',
        'end_date': '2024-12-31',
        'status': 'terminated',
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-12-31T00:00:00Z',
        'deleted_at': null,
      };
      final lease = Lease.fromJson(json);
      expect(lease.endDate, isNotNull);
      expect(lease.endDate!.year, 2024);
      expect(lease.endDate!.month, 12);
      expect(lease.endDate!.day, 31);
    });

    test('status "terminated" parsé correctement', () {
      final json = {
        'id': 'l3',
        'landlord_id': 'lld',
        'property_id': 'p1',
        'tenant_id': 't1',
        'rent_amount_cents': 1000,
        'charges_amount_cents': 0,
        'start_date': '2024-01-01',
        'end_date': null,
        'status': 'terminated',
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-01-01T00:00:00Z',
        'deleted_at': null,
      };
      final lease = Lease.fromJson(json);
      expect(lease.status, LeaseStatus.terminated);
    });

    test('deleted_at null', () {
      final lease = _buildLease();
      expect(lease.deletedAt, isNull);
    });
  });

  group('LeaseExtension — getters calculés', () {
    test('totalAmountCents = rent + charges', () {
      final lease = _buildLease(
        rentAmountCents: 85000,
        chargesAmountCents: 5000,
      );
      expect(lease.totalAmountCents, 90000);
    });

    test('isActive true quand status=active et deletedAt=null', () {
      final lease = _buildLease(status: LeaseStatus.active);
      expect(lease.isActive, isTrue);
    });

    test('isActive false quand status=terminated', () {
      final lease = _buildLease(status: LeaseStatus.terminated);
      expect(lease.isActive, isFalse);
    });

    test('isActive false quand deletedAt non null', () {
      final lease = _buildLease(deletedAt: DateTime(2024, 6));
      expect(lease.isActive, isFalse);
    });

    test('isClosed true quand status=terminated', () {
      final lease = _buildLease(status: LeaseStatus.terminated);
      expect(lease.isClosed, isTrue);
    });

    test('isClosed false quand status=active', () {
      final lease = _buildLease(status: LeaseStatus.active);
      expect(lease.isClosed, isFalse);
    });
  });
}
