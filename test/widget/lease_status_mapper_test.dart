import 'package:easyrent/features/leases/domain/lease.dart';
import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:easyrent/features/leases/presentation/widgets/lease_status_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Lease _makeLease({
  LeaseStatus status = LeaseStatus.active,
  DateTime? endDate,
}) => Lease(
  id: 'l1',
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

/// Date fictive "aujourd'hui" pour les tests.
final _now = DateTime(2026, 6, 22);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('leaseStatusPill', () {
    test('active, endDate=null → success "Actif"', () {
      final result = leaseStatusPill(_makeLease(), now: _now);

      expect(result.label, 'Actif');
      expect(result.tone.name, 'success');
      expect(result.icon, Icons.check_circle_outline);
    });

    test('active, endDate=today+90j → success "Actif"', () {
      final result = leaseStatusPill(
        _makeLease(endDate: _now.add(const Duration(days: 90))),
        now: _now,
      );

      expect(result.label, 'Actif');
      expect(result.tone.name, 'success');
    });

    test('active, endDate=today+59j → warning "À renouveler"', () {
      final result = leaseStatusPill(
        _makeLease(endDate: _now.add(const Duration(days: 59))),
        now: _now,
      );

      expect(result.label, 'À renouveler');
      expect(result.tone.name, 'warning');
      expect(result.icon, Icons.event_repeat_outlined);
    });

    test(
      'active, endDate=today-10j → success (échu mais actif — pas de retard Phase 1)',
      () {
        // Un bail dont la date de fin est passée mais status toujours active
        // (données incohérentes ou bail en cours de clôture) reste "Actif" en Phase 1.
        final result = leaseStatusPill(
          _makeLease(endDate: _now.subtract(const Duration(days: 10))),
          now: _now,
        );

        // endDate - today = -10 jours → inDays < 60 → warning "À renouveler"
        // (car la condition is < 60, et -10 < 60 est vrai)
        expect(result.label, 'À renouveler');
        expect(result.tone.name, 'warning');
      },
    );

    test('terminated → neutral "Terminé"', () {
      final result = leaseStatusPill(
        _makeLease(status: LeaseStatus.terminated),
        now: _now,
      );

      expect(result.label, 'Terminé');
      expect(result.tone.name, 'neutral');
      expect(result.icon, Icons.lock_outline);
    });

    test('archived → neutral "Archivé"', () {
      final result = leaseStatusPill(
        _makeLease(status: LeaseStatus.archived),
        now: _now,
      );

      expect(result.label, 'Archivé');
      expect(result.tone.name, 'neutral');
      expect(result.icon, Icons.archive_outlined);
    });
  });
}
