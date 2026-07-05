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
  int nonRecoverableChargesCents = 0,
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
    nonRecoverableChargesCents: nonRecoverableChargesCents,
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

    // -------------------------------------------------------------------
    // FEAT-036 — nonRecoverableChargesCents
    // -------------------------------------------------------------------
    test(
      'fromJson SANS non_recoverable_charges_cents (bail pré-036) → 0 (AC-3)',
      () {
        final json = {
          'id': 'lease-legacy',
          'landlord_id': 'lld-1',
          'property_id': 'prop-1',
          'tenant_id': 'ten-1',
          'rent_amount_cents': 90000,
          'charges_amount_cents': 10000,
          'start_date': '2024-01-01',
          'end_date': null,
          'status': 'active',
          'created_at': '2024-01-01T10:00:00Z',
          'updated_at': '2024-01-01T10:00:00Z',
          'deleted_at': null,
        };
        final lease = Lease.fromJson(json);
        expect(lease.nonRecoverableChargesCents, 0);
        // Le montant existant reste conservé et interprété comme récupérable.
        expect(lease.chargesAmountCents, 10000);
      },
    );

    test('fromJson AVEC non_recoverable_charges_cents → valeur lue', () {
      final json = {
        'id': 'lease-036',
        'landlord_id': 'lld-1',
        'property_id': 'prop-1',
        'tenant_id': 'ten-1',
        'rent_amount_cents': 90000,
        'charges_amount_cents': 10000,
        'non_recoverable_charges_cents': 2000,
        'start_date': '2024-01-01',
        'end_date': null,
        'status': 'active',
        'created_at': '2024-01-01T10:00:00Z',
        'updated_at': '2024-01-01T10:00:00Z',
        'deleted_at': null,
      };
      final lease = Lease.fromJson(json);
      expect(lease.nonRecoverableChargesCents, 2000);
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

    // -------------------------------------------------------------------
    // FEAT-036 — ventilation récupérable / non récupérable
    // -------------------------------------------------------------------
    test('recoverableChargesCents == chargesAmountCents (alias)', () {
      final lease = _buildLease(chargesAmountCents: 5000);
      expect(lease.recoverableChargesCents, lease.chargesAmountCents);
      expect(lease.recoverableChargesCents, 5000);
    });

    test(
      'totalChargesCents == chargesAmountCents + nonRecoverableChargesCents',
      () {
        final lease = _buildLease(
          chargesAmountCents: 5000,
          nonRecoverableChargesCents: 2000,
        );
        expect(lease.totalChargesCents, 7000);
      },
    );

    test(
      'totalChargesCents == chargesAmountCents quand non-récupérable = 0',
      () {
        final lease = _buildLease(
          chargesAmountCents: 5000,
          nonRecoverableChargesCents: 0,
        );
        expect(lease.totalChargesCents, 5000);
      },
    );

    test(
      'totalAmountCents INCHANGÉ par FEAT-036 — n\'inclut PAS le non-récupérable',
      () {
        final lease = _buildLease(
          rentAmountCents: 85000,
          chargesAmountCents: 5000,
          nonRecoverableChargesCents: 2000,
        );
        // Loyer CC = loyer + récupérable SEUL (90000), pas 92000.
        expect(lease.totalAmountCents, 90000);
        expect(lease.totalAmountCents, isNot(lease.totalChargesCents + 85000));
      },
    );

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
