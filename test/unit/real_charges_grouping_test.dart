/// Tests de [groupRealCharges] / [groupRealChargesByProperty]
/// (`features/expenses/application/real_charges_grouping.dart`).
///
/// Couvre :
/// - seules les dépenses `non_recoverable` sont retenues
/// - `condo_charges` récupérable par défaut est exclue tant qu'elle n'est
///   pas explicitement overridée en non-récupérable
/// - les natures sans équivalent prévisionnel (`works`, `repair_maintenance`,
///   `management_fees`, `other`) restent hors des 3 buckets, même en
///   non-récupérable
/// - regroupement multi-biens par `propertyId`
library;

import 'package:easyrent/features/expenses/application/real_charges_grouping.dart';
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
  required ExpenseNature nature,
  required ExpenseCategory category,
  int amountCents = 5000,
  DateTime? expenseDate,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: propertyId,
  amountCents: amountCents,
  expenseDate: expenseDate ?? DateTime(2026, 1, 1),
  nature: nature,
  category: category,
  categoryOverridden: nature.defaultCategory != category,
  periodYear: 2026,
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

void main() {
  group('groupRealCharges', () {
    test('taxe foncière et assurance PNO (toujours non récupérables)', () {
      final expenses = [
        _makeExpense(
          nature: ExpenseNature.propertyTax,
          category: ExpenseCategory.nonRecoverable,
          amountCents: 120000,
          expenseDate: DateTime(2026, 3, 1),
        ),
        _makeExpense(
          nature: ExpenseNature.insurancePno,
          category: ExpenseCategory.nonRecoverable,
          amountCents: 30000,
          expenseDate: DateTime(2026, 4, 1),
        ),
      ];

      final result = groupRealCharges(expenses);

      expect(result.propertyTax, hasLength(1));
      expect(result.propertyTax.first.amountCents, 120000);
      expect(result.insurancePno, hasLength(1));
      expect(result.insurancePno.first.amountCents, 30000);
      expect(result.condoFeesNonRecoverable, isEmpty);
    });

    test(
      'charges copro récupérables (par défaut) exclues du bucket non récupérable',
      () {
        final expenses = [
          _makeExpense(
            nature: ExpenseNature.condoCharges,
            category: ExpenseCategory.recoverable, // défaut, pas d'override
            amountCents: 60000,
          ),
        ];

        final result = groupRealCharges(expenses);

        expect(result.condoFeesNonRecoverable, isEmpty);
      },
    );

    test('charges copro overridées en non récupérable → comptées', () {
      final expenses = [
        _makeExpense(
          nature: ExpenseNature.condoCharges,
          category: ExpenseCategory.nonRecoverable, // override explicite
          amountCents: 60000,
        ),
      ];

      final result = groupRealCharges(expenses);

      expect(result.condoFeesNonRecoverable, hasLength(1));
      expect(result.condoFeesNonRecoverable.first.amountCents, 60000);
    });

    test(
      'travaux/entretien/honoraires/autre non récupérables — hors des 3 buckets',
      () {
        final expenses = [
          _makeExpense(
            id: 'e1',
            nature: ExpenseNature.works,
            category: ExpenseCategory.nonRecoverable,
            amountCents: 300000,
          ),
          _makeExpense(
            id: 'e2',
            nature: ExpenseNature.repairMaintenance,
            category: ExpenseCategory.nonRecoverable,
            amountCents: 15000,
          ),
          _makeExpense(
            id: 'e3',
            nature: ExpenseNature.managementFees,
            category: ExpenseCategory.nonRecoverable,
            amountCents: 20000,
          ),
          _makeExpense(
            id: 'e4',
            nature: ExpenseNature.other,
            category: ExpenseCategory.nonRecoverable,
            amountCents: 5000,
          ),
        ];

        final result = groupRealCharges(expenses);

        expect(result.propertyTax, isEmpty);
        expect(result.insurancePno, isEmpty);
        expect(result.condoFeesNonRecoverable, isEmpty);
      },
    );

    test('liste vide → 3 buckets vides', () {
      final result = groupRealCharges(const []);

      expect(result.propertyTax, isEmpty);
      expect(result.insurancePno, isEmpty);
      expect(result.condoFeesNonRecoverable, isEmpty);
    });
  });

  group('groupRealChargesByProperty', () {
    test('regroupe correctement par propertyId', () {
      final expenses = [
        _makeExpense(
          id: 'e1',
          propertyId: 'p1',
          nature: ExpenseNature.propertyTax,
          category: ExpenseCategory.nonRecoverable,
          amountCents: 120000,
        ),
        _makeExpense(
          id: 'e2',
          propertyId: 'p2',
          nature: ExpenseNature.propertyTax,
          category: ExpenseCategory.nonRecoverable,
          amountCents: 90000,
        ),
        _makeExpense(
          id: 'e3',
          propertyId: 'p1',
          nature: ExpenseNature.insurancePno,
          category: ExpenseCategory.nonRecoverable,
          amountCents: 25000,
        ),
      ];

      final result = groupRealChargesByProperty(expenses);

      expect(result.keys, containsAll(['p1', 'p2']));
      expect(result['p1']!.propertyTax.first.amountCents, 120000);
      expect(result['p1']!.insurancePno.first.amountCents, 25000);
      expect(result['p2']!.propertyTax.first.amountCents, 90000);
      expect(result['p2']!.insurancePno, isEmpty);
    });

    test('liste vide → map vide', () {
      final result = groupRealChargesByProperty(const []);
      expect(result, isEmpty);
    });
  });
}
