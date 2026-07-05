/// Tests de sérialisation [Lease] — round-trip JSON, backward compat, nouveaux champs.
///
/// Vérifie notamment que les leases sans les nouveaux champs Phase 3 continuent
/// de fonctionner (backward compat via defaults).
library;

import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:easyrent/features/payments/domain/payment_method.dart';
import 'package:flutter_test/flutter_test.dart';

/// JSON minimal (champs Phase 1-2 seulement, sans Phase 3).
Map<String, dynamic> _jsonLegacy() => {
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

/// JSON complet avec tous les champs Phase 3.
Map<String, dynamic> _jsonFull() => {
  'id': 'lease-full',
  'landlord_id': 'lld-1',
  'property_id': 'prop-1',
  'tenant_id': 'ten-1',
  'rent_amount_cents': 85000,
  'charges_amount_cents': 5000,
  'start_date': '2024-03-01',
  'end_date': '2027-02-28',
  'status': 'active',
  'lease_type': 'furnished',
  'deposit_amount_cents': 170000,
  'payment_day': 5,
  'payment_method': 'prelevement',
  'irl_index_value': 142.43,
  'irl_quarter_ref': 'T1-2024',
  'agency_fees_cents': 50000,
  'solidarity_clause': true,
  'entry_inventory_done': true,
  'non_recoverable_charges_cents': 2000,
  'created_at': '2024-03-01T10:00:00Z',
  'updated_at': '2024-03-01T10:00:00Z',
  'deleted_at': null,
};

void main() {
  // ---------------------------------------------------------------------------
  // Backward compat — JSON legacy sans champs Phase 3
  // ---------------------------------------------------------------------------
  group('Backward compat — JSON legacy (sans champs Phase 3)', () {
    test('fromJson JSON legacy sans lease_type → unfurnished par défaut', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.leaseType, LeaseType.unfurnished);
    });

    test('fromJson JSON legacy → depositAmountCents null', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.depositAmountCents, isNull);
    });

    test('fromJson JSON legacy → paymentDay = 1', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.paymentDay, 1);
    });

    test('fromJson JSON legacy → paymentMethod = virement', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.paymentMethod, PaymentMethod.virement);
    });

    test('fromJson JSON legacy → irlIndexValue null', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.irlIndexValue, isNull);
    });

    test('fromJson JSON legacy → irlQuarterRef null', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.irlQuarterRef, isNull);
    });

    test('fromJson JSON legacy → agencyFeesCents = 0', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.agencyFeesCents, 0);
    });

    test('fromJson JSON legacy → solidarityClause = false', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.solidarityClause, isFalse);
    });

    test('fromJson JSON legacy → entryInventoryDone = false', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.entryInventoryDone, isFalse);
    });

    // FEAT-036 (AC-3) : bail créé avant le champ nonRecoverableChargesCents
    // ⇒ défaut 0, le récupérable existant reste inchangé.
    test('fromJson JSON legacy → nonRecoverableChargesCents = 0', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.nonRecoverableChargesCents, 0);
    });

    test('champs legacy préservés (id, rent, status)', () {
      final lease = Lease.fromJson(_jsonLegacy());
      expect(lease.id, 'lease-legacy');
      expect(lease.rentAmountCents, 90000);
      expect(lease.status, LeaseStatus.active);
    });
  });

  // ---------------------------------------------------------------------------
  // Round-trip JSON complet
  // ---------------------------------------------------------------------------
  group('Round-trip JSON complet', () {
    test('fromJson JSON complet → leaseType = furnished', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.leaseType, LeaseType.furnished);
    });

    test('fromJson JSON complet → depositAmountCents = 170000', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.depositAmountCents, 170000);
    });

    test('fromJson JSON complet → paymentDay = 5', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.paymentDay, 5);
    });

    test('fromJson JSON complet → paymentMethod = prelevement', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.paymentMethod, PaymentMethod.prelevement);
    });

    test('fromJson JSON complet → irlIndexValue = 142.43', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.irlIndexValue, closeTo(142.43, 0.001));
    });

    test('fromJson JSON complet → irlQuarterRef = "T1-2024"', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.irlQuarterRef, 'T1-2024');
    });

    test('fromJson JSON complet → agencyFeesCents = 50000', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.agencyFeesCents, 50000);
    });

    test('fromJson JSON complet → solidarityClause = true', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.solidarityClause, isTrue);
    });

    test('fromJson JSON complet → entryInventoryDone = true', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.entryInventoryDone, isTrue);
    });

    test('fromJson JSON complet → nonRecoverableChargesCents = 2000', () {
      final lease = Lease.fromJson(_jsonFull());
      expect(lease.nonRecoverableChargesCents, 2000);
    });
  });

  // ---------------------------------------------------------------------------
  // Round-trip toJson → fromJson
  // ---------------------------------------------------------------------------
  group('Round-trip toJson → fromJson', () {
    test('Lease complet sérialisé puis désérialisé est identique', () {
      final original = Lease.fromJson(_jsonFull());
      final json = original.toJson();
      final restored = Lease.fromJson(json);

      expect(restored.leaseType, original.leaseType);
      expect(restored.depositAmountCents, original.depositAmountCents);
      expect(restored.paymentDay, original.paymentDay);
      expect(restored.paymentMethod, original.paymentMethod);
      expect(restored.irlIndexValue, original.irlIndexValue);
      expect(restored.irlQuarterRef, original.irlQuarterRef);
      expect(restored.agencyFeesCents, original.agencyFeesCents);
      expect(restored.solidarityClause, original.solidarityClause);
      expect(restored.entryInventoryDone, original.entryInventoryDone);
      expect(
        restored.nonRecoverableChargesCents,
        original.nonRecoverableChargesCents,
      );
    });

    test('lease_type correctement sérialisé en sqlValue', () {
      final lease = Lease.fromJson(_jsonFull());
      final json = lease.toJson();
      expect(json['lease_type'], 'furnished');
    });

    test('payment_method correctement sérialisé', () {
      final lease = Lease.fromJson(_jsonFull());
      final json = lease.toJson();
      expect(json['payment_method'], 'prelevement');
    });

    test('lease_type inconnu → unfurnished (défense)', () {
      final json = _jsonLegacy()..['lease_type'] = 'colocation_propre';
      final lease = Lease.fromJson(json);
      expect(lease.leaseType, LeaseType.unfurnished);
    });
  });

  // ---------------------------------------------------------------------------
  // Valeurs par défaut via constructeur Dart
  // ---------------------------------------------------------------------------
  group('Valeurs par défaut constructeur', () {
    test('leaseType default = unfurnished', () {
      final lease = Lease(
        id: 'l1',
        landlordId: 'lld',
        propertyId: 'p1',
        tenantId: 't1',
        rentAmountCents: 1000,
        chargesAmountCents: 0,
        startDate: DateTime(2024),
        status: LeaseStatus.active,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(lease.leaseType, LeaseType.unfurnished);
    });

    test('paymentDay default = 1', () {
      final lease = Lease(
        id: 'l1',
        landlordId: 'lld',
        propertyId: 'p1',
        tenantId: 't1',
        rentAmountCents: 1000,
        chargesAmountCents: 0,
        startDate: DateTime(2024),
        status: LeaseStatus.active,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(lease.paymentDay, 1);
    });

    test('agencyFeesCents default = 0', () {
      final lease = Lease(
        id: 'l1',
        landlordId: 'lld',
        propertyId: 'p1',
        tenantId: 't1',
        rentAmountCents: 1000,
        chargesAmountCents: 0,
        startDate: DateTime(2024),
        status: LeaseStatus.active,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(lease.agencyFeesCents, 0);
    });

    test('nonRecoverableChargesCents default = 0 (FEAT-036)', () {
      final lease = Lease(
        id: 'l1',
        landlordId: 'lld',
        propertyId: 'p1',
        tenantId: 't1',
        rentAmountCents: 1000,
        chargesAmountCents: 0,
        startDate: DateTime(2024),
        status: LeaseStatus.active,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      expect(lease.nonRecoverableChargesCents, 0);
    });
  });
}
