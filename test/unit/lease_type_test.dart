/// Tests unitaires de [LeaseType].
///
/// Couvre : labelFr, sqlValue, legalMinDurationMonths, maxDepositMonths,
/// fromSql (null-safe, valeur inconnue, toutes les valeurs valides).
library;

import 'package:easyrent/features/leases/domain/lease_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaseType.labelFr', () {
    test('unfurnished → "Vide (non meublé)"', () {
      expect(LeaseType.unfurnished.labelFr, 'Vide (non meublé)');
    });

    test('furnished → "Meublé"', () {
      expect(LeaseType.furnished.labelFr, 'Meublé');
    });

    test('mobility → "Mobilité"', () {
      expect(LeaseType.mobility.labelFr, 'Mobilité');
    });

    test('student → "Étudiant"', () {
      expect(LeaseType.student.labelFr, 'Étudiant');
    });
  });

  group('LeaseType.sqlValue', () {
    test('unfurnished → "unfurnished"', () {
      expect(LeaseType.unfurnished.sqlValue, 'unfurnished');
    });

    test('furnished → "furnished"', () {
      expect(LeaseType.furnished.sqlValue, 'furnished');
    });

    test('mobility → "mobility"', () {
      expect(LeaseType.mobility.sqlValue, 'mobility');
    });

    test('student → "student"', () {
      expect(LeaseType.student.sqlValue, 'student');
    });
  });

  group('LeaseType.legalMinDurationMonths', () {
    test('unfurnished → 36 mois (3 ans)', () {
      expect(LeaseType.unfurnished.legalMinDurationMonths, 36);
    });

    test('furnished → 12 mois (1 an)', () {
      expect(LeaseType.furnished.legalMinDurationMonths, 12);
    });

    test('mobility → 1 mois', () {
      expect(LeaseType.mobility.legalMinDurationMonths, 1);
    });

    test('student → 9 mois', () {
      expect(LeaseType.student.legalMinDurationMonths, 9);
    });
  });

  group('LeaseType.maxDepositMonths', () {
    test('unfurnished → 1 mois de loyer HC max', () {
      expect(LeaseType.unfurnished.maxDepositMonths, 1);
    });

    test('furnished → 2 mois de loyer HC max', () {
      expect(LeaseType.furnished.maxDepositMonths, 2);
    });

    test('mobility → 0 (pas de DG autorisé)', () {
      expect(LeaseType.mobility.maxDepositMonths, 0);
    });

    test('student → 1 mois de loyer HC max', () {
      expect(LeaseType.student.maxDepositMonths, 1);
    });
  });

  group('LeaseType.formHelperText', () {
    test('unfurnished → contient "3 ans"', () {
      expect(LeaseType.unfurnished.formHelperText, contains('3 ans'));
    });

    test('furnished → contient "1 an"', () {
      expect(LeaseType.furnished.formHelperText, contains('1 an'));
    });

    test('mobility → contient "mobilité"', () {
      expect(
        LeaseType.mobility.formHelperText.toLowerCase(),
        contains('mobilité'),
      );
    });

    test('student → contient "9 mois"', () {
      expect(LeaseType.student.formHelperText, contains('9 mois'));
    });
  });

  group('LeaseType.fromSql', () {
    test('null → unfurnished (backward compat)', () {
      expect(LeaseType.fromSql(null), LeaseType.unfurnished);
    });

    test('valeur inconnue → unfurnished (fallback défensif)', () {
      expect(LeaseType.fromSql('some_future_type'), LeaseType.unfurnished);
    });

    test('"unfurnished" → unfurnished', () {
      expect(LeaseType.fromSql('unfurnished'), LeaseType.unfurnished);
    });

    test('"furnished" → furnished', () {
      expect(LeaseType.fromSql('furnished'), LeaseType.furnished);
    });

    test('"mobility" → mobility', () {
      expect(LeaseType.fromSql('mobility'), LeaseType.mobility);
    });

    test('"student" → student', () {
      expect(LeaseType.fromSql('student'), LeaseType.student);
    });

    test('round-trip : sqlValue → fromSql', () {
      for (final t in LeaseType.values) {
        expect(LeaseType.fromSql(t.sqlValue), t);
      }
    });
  });
}
