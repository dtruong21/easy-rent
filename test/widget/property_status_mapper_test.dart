import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_list_item.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/properties/presentation/widgets/property_status_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Property _makeProperty({String id = 'p1'}) => Property(
  id: id,
  landlordId: 'owner',
  name: 'Appartement Test',
  address: '1 rue Test, 75001 Paris',
  type: PropertyType.appartement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

PropertyListItem _makeItem({
  String? activeLeaseId,
  String? tenantName,
  String? rentLabel,
}) => PropertyListItem(
  property: _makeProperty(),
  activeLeaseId: activeLeaseId,
  currentTenantName: tenantName,
  currentRentLabel: rentLabel,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('propertyOccupancyPill', () {
    test('bail actif → success "Loué"', () {
      final item = _makeItem(
        activeLeaseId: 'l1',
        tenantName: 'Jean Dupont',
        rentLabel: '1 200,00 € CC / mois',
      );

      final result = propertyOccupancyPill(item);

      expect(result.label, 'Loué');
      expect(result.tone.name, 'success');
      expect(result.icon, Icons.home_filled);
    });

    test('pas de bail → warning "Vacant"', () {
      final item = _makeItem();

      final result = propertyOccupancyPill(item);

      expect(result.label, 'Vacant');
      expect(result.tone.name, 'warning');
      expect(result.icon, Icons.home_work_outlined);
    });

    test('bail actif sans loyer → success "Loué" (loyer null toléré)', () {
      final item = _makeItem(
        activeLeaseId: 'l2',
        tenantName: 'Marie Martin',
        // rentLabel null — champ optionnel
      );

      final result = propertyOccupancyPill(item);

      expect(result.label, 'Loué');
      expect(result.tone.name, 'success');
    });

    test('bail actif sans locataire → success "Loué" (tenant null toléré)', () {
      final item = _makeItem(
        activeLeaseId: 'l3',
        // tenantName null — champ optionnel
        rentLabel: '800,00 € CC / mois',
      );

      final result = propertyOccupancyPill(item);

      expect(result.label, 'Loué');
      expect(result.tone.name, 'success');
    });
  });
}
