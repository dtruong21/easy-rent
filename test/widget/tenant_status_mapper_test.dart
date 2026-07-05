import 'package:easyrent/core/ui/cards/status_pill_tone.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:easyrent/features/tenants/domain/tenant_list_item.dart';
import 'package:easyrent/features/tenants/presentation/widgets/tenant_status_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Tenant _makeTenant({String id = 't1'}) => Tenant(
  id: id,
  landlordId: 'owner-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: 'jean@test.com',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

TenantListItem _makeItem({String? activeLeaseId}) => TenantListItem(
  tenant: _makeTenant(),
  activeLeaseId: activeLeaseId,
  currentPropertyName: activeLeaseId != null ? 'Appartement Test' : null,
  activeLeasePeriodLabel: activeLeaseId != null ? 'Depuis 01/01/2024' : null,
  activeLeaseRentCents: activeLeaseId != null ? 80000 : null,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('tenantOccupancyPill', () {
    test('locataire avec bail actif → tone success, label "Actif"', () {
      final item = _makeItem(activeLeaseId: 'lease-123');
      final pill = tenantOccupancyPill(item);

      expect(pill.tone, StatusPillTone.success);
      expect(pill.label, 'Actif');
      expect(pill.icon, isA<IconData>());
    });

    test('locataire sans bail → tone warning, label "Sans bail"', () {
      final item = _makeItem(activeLeaseId: null);
      final pill = tenantOccupancyPill(item);

      expect(pill.tone, StatusPillTone.warning);
      expect(pill.label, 'Sans bail');
      expect(pill.icon, isA<IconData>());
    });

    test('locataire avec bail actif → icône différente de sans bail', () {
      final withLease = tenantOccupancyPill(_makeItem(activeLeaseId: 'l1'));
      final withoutLease = tenantOccupancyPill(_makeItem(activeLeaseId: null));

      expect(withLease.icon, isNot(equals(withoutLease.icon)));
    });
  });
}
