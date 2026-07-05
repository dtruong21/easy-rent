/// Tests unitaires de [LeaseStatus].
library;

import 'package:easyrent/features/leases/domain/lease_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaseStatus.fromSql', () {
    test('"active" → LeaseStatus.active', () {
      expect(LeaseStatus.fromSql('active'), LeaseStatus.active);
    });

    test('"terminated" → LeaseStatus.terminated', () {
      expect(LeaseStatus.fromSql('terminated'), LeaseStatus.terminated);
    });

    test('"archived" → LeaseStatus.archived', () {
      expect(LeaseStatus.fromSql('archived'), LeaseStatus.archived);
    });

    test('valeur inconnue → LeaseStatus.archived (tolérance défensive)', () {
      expect(LeaseStatus.fromSql('unknown_future_value'), LeaseStatus.archived);
    });
  });

  group('LeaseStatus.labelFr', () {
    test('active → "Actif"', () {
      expect(LeaseStatus.active.labelFr, 'Actif');
    });

    test('terminated → "Terminé"', () {
      expect(LeaseStatus.terminated.labelFr, 'Terminé');
    });

    test('archived → "Archivé"', () {
      expect(LeaseStatus.archived.labelFr, 'Archivé');
    });
  });

  group('LeaseStatus.sqlValue', () {
    test('active → "active"', () {
      expect(LeaseStatus.active.sqlValue, 'active');
    });

    test('terminated → "terminated"', () {
      expect(LeaseStatus.terminated.sqlValue, 'terminated');
    });

    test('archived → "archived"', () {
      expect(LeaseStatus.archived.sqlValue, 'archived');
    });
  });
}
