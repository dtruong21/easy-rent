/// Tests unitaires du [ExpenseFormController] — focus FEAT-041b : câblage
/// du justificatif (`documentId`) vers `ExpensesRepository.create`/`update`.
library;

import 'package:easyrent/features/expenses/application/expense_form_controller.dart';
import 'package:easyrent/features/expenses/data/expenses_repository.dart';
import 'package:easyrent/features/expenses/domain/expense.dart';
import 'package:easyrent/features/expenses/domain/expense_category.dart';
import 'package:easyrent/features/expenses/domain/expense_form_state.dart';
import 'package:easyrent/features/expenses/domain/expense_nature.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeExpensesRepository implements ExpensesRepository {
  bool createCalled = false;
  bool updateCalled = false;
  String? lastCreateDocumentId;
  String? lastUpdateDocumentId;
  Exception? createError;

  @override
  Future<Expense> create({
    required String propertyId,
    String? leaseId,
    required int amountCents,
    required DateTime expenseDate,
    required ExpenseNature nature,
    ExpenseCategory? category,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? periodYear,
    String? documentId,
    String? notes,
  }) async {
    createCalled = true;
    lastCreateDocumentId = documentId;
    final err = createError;
    if (err != null) throw err;
    return _makeExpense(
      propertyId: propertyId,
      leaseId: leaseId,
      amountCents: amountCents,
      expenseDate: expenseDate,
      nature: nature,
      category: category ?? nature.defaultCategory,
      periodYear: periodYear ?? expenseDate.year,
      documentId: documentId,
      notes: notes,
    );
  }

  @override
  Future<Expense> update(Expense expense) async {
    updateCalled = true;
    lastUpdateDocumentId = expense.documentId;
    return expense;
  }

  @override
  Future<void> archive(String id) async {}

  @override
  Future<Expense> getById(String id) async => throw UnimplementedError();

  @override
  Future<List<Expense>> listForProperty(String propertyId) async => [];

  @override
  Stream<List<Expense>> watchForProperty(String propertyId) => Stream.value([]);
}

Expense _makeExpense({
  String id = 'expense-1',
  String propertyId = 'property-1',
  String? leaseId,
  int amountCents = 45000,
  DateTime? expenseDate,
  ExpenseNature nature = ExpenseNature.condoCharges,
  ExpenseCategory category = ExpenseCategory.recoverable,
  int periodYear = 2025,
  String? documentId,
  String? notes,
}) => Expense(
  id: id,
  landlordId: 'landlord-1',
  propertyId: propertyId,
  leaseId: leaseId,
  amountCents: amountCents,
  expenseDate: expenseDate ?? DateTime(2025, 3, 15),
  nature: nature,
  category: category,
  periodYear: periodYear,
  documentId: documentId,
  notes: notes,
  createdAt: DateTime(2025, 3, 15),
  updatedAt: DateTime(2025, 3, 15),
);

ExpenseFormController _makeController(_FakeExpensesRepository repo) {
  final container = ProviderContainer(
    overrides: [expensesRepositoryProvider.overrideWithValue(repo)],
  );
  return container.read(expenseFormControllerProvider.notifier);
}

bool _isSuccess(ExpenseFormState s) =>
    s.maybeWhen(success: (_) => true, orElse: () => false);

void main() {
  group('ExpenseFormController — création avec justificatif (FEAT-041b)', () {
    test(
      'documentId fourni est transmis tel quel à ExpensesRepository.create',
      () async {
        final repo = _FakeExpensesRepository();
        final ctrl = _makeController(repo);

        await ctrl.submit(
          propertyId: 'property-1',
          amountCents: 45000,
          expenseDate: DateTime(2025, 3, 15),
          nature: ExpenseNature.condoCharges,
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
          documentId: 'doc-receipt-1',
        );

        expect(repo.createCalled, isTrue);
        expect(repo.lastCreateDocumentId, 'doc-receipt-1');
        expect(_isSuccess(ctrl.state), isTrue);
      },
    );

    test(
      'aucun justificatif joint (recommandé, non bloquant) → documentId null '
      "n'empêche pas la création",
      () async {
        final repo = _FakeExpensesRepository();
        final ctrl = _makeController(repo);

        await ctrl.submit(
          propertyId: 'property-1',
          amountCents: 45000,
          expenseDate: DateTime(2025, 3, 15),
          nature: ExpenseNature.propertyTax,
        );

        expect(repo.createCalled, isTrue);
        expect(repo.lastCreateDocumentId, isNull);
        expect(_isSuccess(ctrl.state), isTrue);
      },
    );

    test('erreur du repo → état error, documentId a bien été transmis avant '
        "l'échec", () async {
      final repo = _FakeExpensesRepository()
        ..createError = Exception('createExpense failed');
      final ctrl = _makeController(repo);

      await ctrl.submit(
        propertyId: 'property-1',
        amountCents: 45000,
        expenseDate: DateTime(2025, 3, 15),
        nature: ExpenseNature.propertyTax,
        documentId: 'doc-receipt-1',
      );

      expect(repo.lastCreateDocumentId, 'doc-receipt-1');
      expect(
        ctrl.state.maybeWhen(error: (_) => true, orElse: () => false),
        isTrue,
      );
    });
  });

  group('ExpenseFormController — édition avec justificatif (FEAT-041b)', () {
    test(
      'nouveau documentId fourni en édition écrase le documentId existant',
      () async {
        final repo = _FakeExpensesRepository();
        final ctrl = _makeController(repo);
        final initial = _makeExpense(documentId: 'doc-old');

        await ctrl.submit(
          initial: initial,
          propertyId: 'property-1',
          amountCents: 45000,
          expenseDate: DateTime(2025, 3, 15),
          nature: ExpenseNature.condoCharges,
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
          documentId: 'doc-new',
        );

        expect(repo.updateCalled, isTrue);
        expect(repo.lastUpdateDocumentId, 'doc-new');
      },
    );

    test(
      'documentId non fourni en édition conserve le documentId existant',
      () async {
        final repo = _FakeExpensesRepository();
        final ctrl = _makeController(repo);
        final initial = _makeExpense(documentId: 'doc-old');

        await ctrl.submit(
          initial: initial,
          propertyId: 'property-1',
          amountCents: 45000,
          expenseDate: DateTime(2025, 3, 15),
          nature: ExpenseNature.condoCharges,
          periodStart: DateTime(2025, 1, 1),
          periodEnd: DateTime(2025, 12, 31),
        );

        expect(repo.updateCalled, isTrue);
        expect(repo.lastUpdateDocumentId, 'doc-old');
      },
    );
  });
}
