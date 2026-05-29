/// Tests unitaires de [LeaseFormValidators].
library;

import 'package:easyrent/core/utils/lease_form_validators.dart';
import 'package:easyrent/features/properties/domain/property.dart';
import 'package:easyrent/features/properties/domain/property_type.dart';
import 'package:easyrent/features/tenants/domain/tenant.dart';
import 'package:flutter_test/flutter_test.dart';

Property _fakeProperty() => Property(
  id: 'p1',
  landlordId: 'lld',
  name: 'Appart',
  address: '1 rue Test',
  type: PropertyType.appartement,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

Tenant _fakeTenant() => Tenant(
  id: 't1',
  landlordId: 'lld',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: 'jean@test.com',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  group('validateProperty', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateProperty(null), isNotNull);
    });

    test('property sélectionnée → null', () {
      expect(LeaseFormValidators.validateProperty(_fakeProperty()), isNull);
    });
  });

  group('validateTenant', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateTenant(null), isNotNull);
    });

    test('tenant sélectionné → null', () {
      expect(LeaseFormValidators.validateTenant(_fakeTenant()), isNull);
    });
  });

  group('validateRentAmount', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateRentAmount(null), isNotNull);
    });

    test('vide → erreur', () {
      expect(LeaseFormValidators.validateRentAmount(''), isNotNull);
    });

    test('"0" → erreur (doit être > 0)', () {
      expect(LeaseFormValidators.validateRentAmount('0'), isNotNull);
    });

    test('négatif "-100" → erreur', () {
      expect(LeaseFormValidators.validateRentAmount('-100'), isNotNull);
    });

    test('"abc" → erreur', () {
      expect(LeaseFormValidators.validateRentAmount('abc'), isNotNull);
    });

    test('"850" → null', () {
      expect(LeaseFormValidators.validateRentAmount('850'), isNull);
    });

    test('"850,00" (virgule) → null', () {
      expect(LeaseFormValidators.validateRentAmount('850,00'), isNull);
    });

    test('"0.01" → null (centimes positifs)', () {
      expect(LeaseFormValidators.validateRentAmount('0.01'), isNull);
    });

    // --- Plafond 100 000 000 centimes = 1 000 000,00 € (Fix 2) ---
    // 999 999,99 € × 100 = 99 999 999 centimes ≤ cap → accepté
    test('"999999.99" (99 999 999 cts, sous le plafond) → null', () {
      expect(LeaseFormValidators.validateRentAmount('999999.99'), isNull);
    });

    // 1 000 000,00 € × 100 = 100 000 000 centimes == cap → accepté (> strict)
    test('"1000000.00" (100 000 000 cts, exactement au plafond) → null', () {
      expect(LeaseFormValidators.validateRentAmount('1000000.00'), isNull);
    });

    // 1 000 000,01 € × 100 = 100 000 001 centimes > cap → rejeté
    test('"1000000.01" (100 000 001 cts, au-delà du plafond) → erreur', () {
      expect(LeaseFormValidators.validateRentAmount('1000000.01'), isNotNull);
    });
  });

  group('validateChargesAmount', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateChargesAmount(null), isNotNull);
    });

    test('vide → erreur', () {
      expect(LeaseFormValidators.validateChargesAmount(''), isNotNull);
    });

    test('"0" → null (zéro accepté)', () {
      expect(LeaseFormValidators.validateChargesAmount('0'), isNull);
    });

    test('"50,00" → null', () {
      expect(LeaseFormValidators.validateChargesAmount('50,00'), isNull);
    });

    test('négatif "-10" → erreur', () {
      expect(LeaseFormValidators.validateChargesAmount('-10'), isNotNull);
    });

    test('"abc" → erreur', () {
      expect(LeaseFormValidators.validateChargesAmount('abc'), isNotNull);
    });

    // --- Plafond charges (Fix 2) ---
    test('"999999.99" (99 999 999 cts, sous le plafond) → null', () {
      expect(LeaseFormValidators.validateChargesAmount('999999.99'), isNull);
    });

    test('"1000000.01" (100 000 001 cts, au-delà du plafond) → erreur', () {
      expect(
        LeaseFormValidators.validateChargesAmount('1000000.01'),
        isNotNull,
      );
    });
  });

  group('validateStartDate', () {
    test('null → erreur', () {
      expect(LeaseFormValidators.validateStartDate(null), isNotNull);
    });

    test('date fournie → null', () {
      expect(
        LeaseFormValidators.validateStartDate(DateTime(2024, 1, 1)),
        isNull,
      );
    });

    // --- Bornes absolues 1900-01-01 … 2100-12-31 (Fix 3) ---
    test('2026-06-01 (dans la plage) → null', () {
      expect(
        LeaseFormValidators.validateStartDate(DateTime(2026, 6, 1)),
        isNull,
      );
    });

    test('1899-12-31 (avant 1900) → erreur', () {
      expect(
        LeaseFormValidators.validateStartDate(DateTime(1899, 12, 31)),
        isNotNull,
      );
    });

    test('2101-01-01 (après 2100) → erreur', () {
      expect(
        LeaseFormValidators.validateStartDate(DateTime(2101, 1, 1)),
        isNotNull,
      );
    });

    test('1900-01-01 (borne basse exacte) → null', () {
      expect(LeaseFormValidators.validateStartDate(DateTime(1900)), isNull);
    });

    test('2100-12-31 (borne haute exacte) → null', () {
      expect(
        LeaseFormValidators.validateStartDate(DateTime(2100, 12, 31)),
        isNull,
      );
    });
  });

  group('validateEndDate', () {
    test('endDate null → null (CDI)', () {
      expect(
        LeaseFormValidators.validateEndDate(null, DateTime(2024, 1, 1)),
        isNull,
      );
    });

    test('endDate > startDate → null', () {
      expect(
        LeaseFormValidators.validateEndDate(
          DateTime(2024, 12, 31),
          DateTime(2024, 1, 1),
        ),
        isNull,
      );
    });

    test('endDate == startDate → erreur', () {
      final date = DateTime(2024, 6, 1);
      expect(LeaseFormValidators.validateEndDate(date, date), isNotNull);
    });

    test('endDate < startDate → erreur', () {
      expect(
        LeaseFormValidators.validateEndDate(
          DateTime(2024, 1, 1),
          DateTime(2024, 12, 31),
        ),
        isNotNull,
      );
    });

    test('endDate fournie mais startDate null → null (pas de cross-check)', () {
      expect(
        LeaseFormValidators.validateEndDate(DateTime(2024, 6), null),
        isNull,
      );
    });

    // --- Bornes absolues end date (Fix 3) ---
    test('endDate 2101-01-01 (après 2100) → erreur', () {
      expect(
        LeaseFormValidators.validateEndDate(
          DateTime(2101, 1, 1),
          DateTime(2026, 1, 1),
        ),
        isNotNull,
      );
    });

    test('endDate 1899-12-31 (avant 1900) → erreur', () {
      expect(
        LeaseFormValidators.validateEndDate(
          DateTime(1899, 12, 31),
          DateTime(2026, 1, 1),
        ),
        isNotNull,
      );
    });

    test('endDate 2026-06-01 dans la plage et > startDate → null', () {
      expect(
        LeaseFormValidators.validateEndDate(
          DateTime(2026, 6, 1),
          DateTime(2026, 1, 1),
        ),
        isNull,
      );
    });
  });
}
