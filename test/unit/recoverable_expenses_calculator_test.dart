/// Tests de [sumRecoverableExpensesForPeriod] (FEAT-041c).
///
/// Couvre :
/// - somme correcte sur des dépenses récupérables qui recouvrent la période
/// - exclusion des dépenses hors période (avant / après)
/// - recouvrement partiel aux bornes (inclusion totale, pas de proratisation)
/// - exclusion STRICTE des dépenses `non_recoverable` (garde-fou décret
///   87-713), même si leur période recouvre la référence
/// - filtre optionnel par `leaseId`
/// - liste vide → 0 (non-régression V1 : pré-remplissage à 0)
/// - piège de fuseau horaire : comparaison de `DateTime` UTC (tel que relu
///   depuis Firestore) contre une période de référence en heure locale —
///   même piège que `charge_provisions_calculator_test.dart`.
library;

import 'package:easyrent/features/charge_regularization/application/recoverable_expenses_calculator.dart';
import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Expense _makeExpense({
  String id = 'exp-1',
  String propertyId = 'property-1',
  String? leaseId = 'lease-1',
  required DateTime periodStart,
  required DateTime periodEnd,
  int amountCents = 5000,
  ExpenseCategory category = ExpenseCategory.recoverable,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: propertyId,
  leaseId: leaseId,
  amountCents: amountCents,
  expenseDate: periodStart,
  nature: ExpenseNature.condoCharges,
  category: category,
  periodYear: periodStart.year,
  periodStart: periodStart,
  periodEnd: periodEnd,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('sumRecoverableExpensesForPeriod — cas de base', () {
    test('somme correcte de plusieurs dépenses dans la période', () {
      final expenses = [
        _makeExpense(
          id: 'e1',
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 1, 31),
          amountCents: 5000,
        ),
        _makeExpense(
          id: 'e2',
          periodStart: DateTime(2025, 2, 1),
          periodEnd: DateTime(2025, 2, 28),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 10000);
    });

    test('0 dépense → 0 (non-régression V1 : pré-remplissage à 0)', () {
      final total = sumRecoverableExpensesForPeriod(
        expenses: const [],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });
  });

  group('sumRecoverableExpensesForPeriod — exclusion hors période', () {
    test('dépense entièrement avant la période → exclue', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2024, 1, 1),
          periodEnd: DateTime(2024, 1, 31),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });

    test('dépense entièrement après la période → exclue', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });

    test('mix dépenses dans/hors période → seules celles dans la période '
        'comptent', () {
      final expenses = [
        _makeExpense(
          id: 'before',
          periodStart: DateTime(2024, 12, 1),
          periodEnd: DateTime(2024, 12, 31),
          amountCents: 9999,
        ),
        _makeExpense(
          id: 'inside',
          periodStart: DateTime(2025, 6, 1),
          periodEnd: DateTime(2025, 6, 30),
          amountCents: 5000,
        ),
        _makeExpense(
          id: 'after',
          periodStart: DateTime(2026, 2, 1),
          periodEnd: DateTime(2026, 2, 28),
          amountCents: 9999,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });
  });

  group('sumRecoverableExpensesForPeriod — recouvrement aux bornes', () {
    test('dépense à cheval sur le début de période → incluse en totalité '
        '(pas de proratisation)', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2024, 12, 15),
          periodEnd: DateTime(2025, 1, 15),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });

    test('dépense à cheval sur la fin de période → incluse en totalité', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2025, 12, 15),
          periodEnd: DateTime(2026, 1, 15),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });

    test('dépense exactement égale à la période de référence → incluse', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
          amountCents: 12000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 12000);
    });

    test('periodEnd de la dépense == referenceStart (1 jour de '
        'recouvrement) → incluse', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2024, 12, 1),
          periodEnd: DateTime(2025, 1, 1),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 5000);
    });

    test('periodStart de la dépense == referenceEnd + 1 jour → exclue '
        '(aucun recouvrement)', () {
      final expenses = [
        _makeExpense(
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 1, 31),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });
  });

  group(
    'sumRecoverableExpensesForPeriod — exclusion STRICTE des non_recoverable '
    '(garde-fou décret 87-713)',
    () {
      test('dépense non-récupérable dans la période → EXCLUE malgré le '
          'recouvrement', () {
        final expenses = [
          _makeExpense(
            periodStart: DateTime(2025, 6, 1),
            periodEnd: DateTime(2025, 6, 30),
            amountCents: 99900,
            category: ExpenseCategory.nonRecoverable,
          ),
        ];
        final total = sumRecoverableExpensesForPeriod(
          expenses: expenses,
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );
        expect(total, 0);
      });

      test('mix récupérable + non-récupérable → seule la part récupérable '
          'compte', () {
        final expenses = [
          _makeExpense(
            id: 'recoverable',
            periodStart: DateTime(2025, 3, 1),
            periodEnd: DateTime(2025, 3, 31),
            amountCents: 5000,
          ),
          _makeExpense(
            id: 'non-recoverable',
            periodStart: DateTime(2025, 3, 1),
            periodEnd: DateTime(2025, 3, 31),
            amountCents: 999900,
            category: ExpenseCategory.nonRecoverable,
          ),
        ];
        final total = sumRecoverableExpensesForPeriod(
          expenses: expenses,
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );
        expect(total, 5000);
      });
    },
  );

  group('sumRecoverableExpensesForPeriod — filtre optionnel leaseId', () {
    test('leaseId fourni → seules les dépenses de ce bail comptent', () {
      final expenses = [
        _makeExpense(
          id: 'lease-a',
          leaseId: 'lease-a',
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 5000,
        ),
        _makeExpense(
          id: 'lease-b',
          leaseId: 'lease-b',
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 7000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
        leaseId: 'lease-a',
      );
      expect(total, 5000);
    });

    test('leaseId null (défaut) → toutes les dépenses récupérables comptent, '
        'y compris celles sans bail rattaché', () {
      final expenses = [
        _makeExpense(
          id: 'with-lease',
          leaseId: 'lease-a',
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 5000,
        ),
        _makeExpense(
          id: 'no-lease',
          leaseId: null,
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 7000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 12000);
    });

    test('leaseId fourni ne correspondant à aucune dépense → 0', () {
      final expenses = [
        _makeExpense(
          id: 'e1',
          leaseId: 'lease-a',
          periodStart: DateTime(2025, 3, 1),
          periodEnd: DateTime(2025, 3, 31),
          amountCents: 5000,
        ),
      ];
      final total = sumRecoverableExpensesForPeriod(
        expenses: expenses,
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
        leaseId: 'lease-unknown',
      );
      expect(total, 0);
    });
  });

  group('sumRecoverableExpensesForPeriod — dépense récupérable sans période '
      '(défensif)', () {
    test('periodStart/periodEnd null → exclue sans lever d\'exception', () {
      final expense = Expense(
        id: 'no-period',
        landlordId: 'landlord-1',
        propertyId: 'property-1',
        leaseId: 'lease-1',
        amountCents: 5000,
        expenseDate: DateTime(2025, 3, 15),
        nature: ExpenseNature.condoCharges,
        category: ExpenseCategory.recoverable,
        periodYear: 2025,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final total = sumRecoverableExpensesForPeriod(
        expenses: [expense],
        referenceStart: DateTime(2025, 1, 1),
        referenceEnd: DateTime(2025, 12, 31),
      );
      expect(total, 0);
    });
  });

  group(
    'sumRecoverableExpensesForPeriod — invariant round-trip UTC (régression '
    'fuseau horaire, même pattern que charge_provisions_calculator_test.dart)',
    () {
      // En chaîne de prod, `periodStart`/`periodEnd` d'une [Expense] relue
      // depuis Firestore sont écrits `.toUtc().toIso8601String()` puis
      // reparsés (`firestoreDocToSnakeJson`) — `DateTime.parse` sur cette
      // chaîne suffixée `Z` renvoie un `DateTime` UTC, pas local. Ce test
      // vérifie l'INVARIANT que la fonction doit respecter : le total
      // calculé ne doit PAS dépendre de la forme (locale vs
      // UTC-round-trippée) sous laquelle la même date civile est passée.
      DateTime roundTripUtc(DateTime local) =>
          DateTime.parse(local.toUtc().toIso8601String());

      test('période de dépense UTC-round-trippée donne le MÊME total que la '
          'forme locale équivalente', () {
        final periodStartLocal = DateTime(2025, 1, 1);
        final periodEndLocal = DateTime(2025, 1, 31);

        final expenseLocal = _makeExpense(
          periodStart: periodStartLocal,
          periodEnd: periodEndLocal,
          amountCents: 5000,
        );
        final expenseRoundTripped = _makeExpense(
          periodStart: roundTripUtc(periodStartLocal),
          periodEnd: roundTripUtc(periodEndLocal),
          amountCents: 5000,
        );

        final totalLocal = sumRecoverableExpensesForPeriod(
          expenses: [expenseLocal],
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );
        final totalRoundTripped = sumRecoverableExpensesForPeriod(
          expenses: [expenseRoundTripped],
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );

        expect(totalRoundTripped, totalLocal);
        expect(totalRoundTripped, 5000);
      });

      test('référence de période UTC-round-trippée donne le MÊME total que la '
          'forme locale équivalente', () {
        final expense = _makeExpense(
          periodStart: DateTime(2025, 6, 1),
          periodEnd: DateTime(2025, 6, 30),
          amountCents: 7500,
        );

        final totalLocal = sumRecoverableExpensesForPeriod(
          expenses: [expense],
          referenceStart: DateTime(2025, 1, 1),
          referenceEnd: DateTime(2025, 12, 31),
        );
        final totalRoundTripped = sumRecoverableExpensesForPeriod(
          expenses: [expense],
          referenceStart: roundTripUtc(DateTime(2025, 1, 1)),
          referenceEnd: roundTripUtc(DateTime(2025, 12, 31)),
        );

        expect(totalRoundTripped, totalLocal);
        expect(totalRoundTripped, 7500);
      });
    },
  );
}
