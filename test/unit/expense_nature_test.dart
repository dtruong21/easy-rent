/// Tests de [ExpenseNature] — table `NATURE_DEFAULT_CATEGORY` (réplique
/// Dart), verrouillage de catégorie, round-trip fromSql/sqlValue.
library;

import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseNature.fromSql', () {
    test('"condo_charges" → ExpenseNature.condoCharges', () {
      expect(
        ExpenseNature.fromSql('condo_charges'),
        ExpenseNature.condoCharges,
      );
    });

    test('"property_tax" → ExpenseNature.propertyTax', () {
      expect(ExpenseNature.fromSql('property_tax'), ExpenseNature.propertyTax);
    });

    test('"insurance_pno" → ExpenseNature.insurancePno', () {
      expect(
        ExpenseNature.fromSql('insurance_pno'),
        ExpenseNature.insurancePno,
      );
    });

    test('"management_fees" → ExpenseNature.managementFees', () {
      expect(
        ExpenseNature.fromSql('management_fees'),
        ExpenseNature.managementFees,
      );
    });

    test('"works" → ExpenseNature.works', () {
      expect(ExpenseNature.fromSql('works'), ExpenseNature.works);
    });

    test('"repair_maintenance" → ExpenseNature.repairMaintenance', () {
      expect(
        ExpenseNature.fromSql('repair_maintenance'),
        ExpenseNature.repairMaintenance,
      );
    });

    test('"other" → ExpenseNature.other', () {
      expect(ExpenseNature.fromSql('other'), ExpenseNature.other);
    });

    test('valeur inconnue → ExpenseNature.other (tolérance défensive)', () {
      expect(ExpenseNature.fromSql('inconnu'), ExpenseNature.other);
    });

    test('chaîne vide → ExpenseNature.other (tolérance défensive)', () {
      expect(ExpenseNature.fromSql(''), ExpenseNature.other);
    });
  });

  group('ExpenseNature.sqlValue', () {
    test('condoCharges.sqlValue == "condo_charges"', () {
      expect(ExpenseNature.condoCharges.sqlValue, 'condo_charges');
    });

    test('propertyTax.sqlValue == "property_tax"', () {
      expect(ExpenseNature.propertyTax.sqlValue, 'property_tax');
    });

    test('insurancePno.sqlValue == "insurance_pno"', () {
      expect(ExpenseNature.insurancePno.sqlValue, 'insurance_pno');
    });

    test('managementFees.sqlValue == "management_fees"', () {
      expect(ExpenseNature.managementFees.sqlValue, 'management_fees');
    });

    test('works.sqlValue == "works"', () {
      expect(ExpenseNature.works.sqlValue, 'works');
    });

    test('repairMaintenance.sqlValue == "repair_maintenance"', () {
      expect(ExpenseNature.repairMaintenance.sqlValue, 'repair_maintenance');
    });

    test('other.sqlValue == "other"', () {
      expect(ExpenseNature.other.sqlValue, 'other');
    });
  });

  group('Round-trip fromSql → sqlValue', () {
    for (final nature in ExpenseNature.values) {
      test('${nature.name} : round-trip cohérent', () {
        final roundTripped = ExpenseNature.fromSql(nature.sqlValue);
        expect(roundTripped, nature);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Table NATURE_DEFAULT_CATEGORY (réplique fidèle côté Dart) — plan § a).
  // ---------------------------------------------------------------------------
  group('ExpenseNature.defaultCategory', () {
    test('condoCharges → recoverable', () {
      expect(
        ExpenseNature.condoCharges.defaultCategory,
        ExpenseCategory.recoverable,
      );
    });

    test('propertyTax → nonRecoverable', () {
      expect(
        ExpenseNature.propertyTax.defaultCategory,
        ExpenseCategory.nonRecoverable,
      );
    });

    test('insurancePno → nonRecoverable', () {
      expect(
        ExpenseNature.insurancePno.defaultCategory,
        ExpenseCategory.nonRecoverable,
      );
    });

    test('managementFees → nonRecoverable', () {
      expect(
        ExpenseNature.managementFees.defaultCategory,
        ExpenseCategory.nonRecoverable,
      );
    });

    test('works → nonRecoverable', () {
      expect(
        ExpenseNature.works.defaultCategory,
        ExpenseCategory.nonRecoverable,
      );
    });

    test('repairMaintenance → nonRecoverable', () {
      expect(
        ExpenseNature.repairMaintenance.defaultCategory,
        ExpenseCategory.nonRecoverable,
      );
    });

    test('other → nonRecoverable', () {
      expect(
        ExpenseNature.other.defaultCategory,
        ExpenseCategory.nonRecoverable,
      );
    });
  });

  group('ExpenseNature.isCategoryLocked', () {
    test('propertyTax est verrouillée', () {
      expect(ExpenseNature.propertyTax.isCategoryLocked, isTrue);
    });

    test('insurancePno est verrouillée', () {
      expect(ExpenseNature.insurancePno.isCategoryLocked, isTrue);
    });

    test('managementFees est verrouillée', () {
      expect(ExpenseNature.managementFees.isCategoryLocked, isTrue);
    });

    test('condoCharges est ajustable (non verrouillée)', () {
      expect(ExpenseNature.condoCharges.isCategoryLocked, isFalse);
    });

    test('works est ajustable (non verrouillée)', () {
      expect(ExpenseNature.works.isCategoryLocked, isFalse);
    });

    test('repairMaintenance est ajustable (non verrouillée)', () {
      expect(ExpenseNature.repairMaintenance.isCategoryLocked, isFalse);
    });

    test('other est ajustable (non verrouillée)', () {
      expect(ExpenseNature.other.isCategoryLocked, isFalse);
    });
  });
}
