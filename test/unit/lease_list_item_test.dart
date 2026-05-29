/// Tests unitaires de [LeaseListItem] — désérialisation jointure PostgREST.
library;

import 'package:easyrent/features/leases/domain/lease_list_item.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _baseJson({
  Map<String, dynamic>? property,
  Map<String, dynamic>? tenant,
}) => {
  'id': 'lease-1',
  'landlord_id': 'lld-1',
  'property_id': 'prop-1',
  'tenant_id': 'ten-1',
  'rent_amount_cents': 85000,
  'charges_amount_cents': 5000,
  'start_date': '2024-01-01',
  'end_date': null,
  'status': 'active',
  'created_at': '2024-01-01T00:00:00Z',
  'updated_at': '2024-01-01T00:00:00Z',
  'deleted_at': null,
  'property': property,
  'tenant': tenant,
};

void main() {
  group('LeaseListItem.fromJson', () {
    test('property et tenant complets — noms affichés', () {
      final item = LeaseListItem.fromJson(
        _baseJson(
          property: {'id': 'prop-1', 'name': 'Appart Lyon'},
          tenant: {'id': 'ten-1', 'first_name': 'Jean', 'last_name': 'Dupont'},
        ),
      );
      expect(item.propertyName, 'Appart Lyon');
      expect(item.tenantDisplayName, 'Jean Dupont');
    });

    test('property null → placeholder "(bien archivé)"', () {
      final item = LeaseListItem.fromJson(
        _baseJson(
          property: null,
          tenant: {'id': 'ten-1', 'first_name': 'Jean', 'last_name': 'Dupont'},
        ),
      );
      expect(item.propertyName, '(bien archivé)');
    });

    test('tenant null → placeholder "(locataire archivé)"', () {
      final item = LeaseListItem.fromJson(
        _baseJson(
          property: {'id': 'prop-1', 'name': 'Maison Bordeaux'},
          tenant: null,
        ),
      );
      expect(item.tenantDisplayName, '(locataire archivé)');
    });

    test('property et tenant tous deux null → deux placeholders', () {
      final item = LeaseListItem.fromJson(
        _baseJson(property: null, tenant: null),
      );
      expect(item.propertyName, '(bien archivé)');
      expect(item.tenantDisplayName, '(locataire archivé)');
    });

    test('lease correctement désérialisé', () {
      final item = LeaseListItem.fromJson(
        _baseJson(
          property: {'id': 'prop-1', 'name': 'Studio Paris'},
          tenant: {'id': 'ten-1', 'first_name': 'Marie', 'last_name': 'Martin'},
        ),
      );
      expect(item.lease.rentAmountCents, 85000);
      expect(item.lease.chargesAmountCents, 5000);
      expect(item.lease.status, LeaseStatus.active);
    });
  });
}
