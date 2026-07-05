import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/expenses_repository.dart';
import '../domain/expense.dart';
import '../domain/expense_filter.dart';

final _log = Logger('PropertyExpensesProvider');

/// Stream temps réel des dépenses actives d'un bien, triées par
/// `expenseDate DESC`.
///
/// Paramétré par `propertyId` — un cache distinct par bien (invalidation
/// chirurgicale). `autoDispose` : pas besoin de conserver le stream ouvert
/// une fois la page fermée.
final propertyExpensesProvider = StreamProvider.autoDispose
    .family<List<Expense>, String>((ref, propertyId) {
      _log.info('watch expenses for property=$propertyId');
      return ref.read(expensesRepositoryProvider).watchForProperty(propertyId);
    });

/// Provider dérivé : dépenses d'un bien filtrées par [ExpenseFilter].
///
/// Paramétré par un tuple (propertyId, filter) — Riverpod compare les
/// enregistrements par valeur (freezed `==`), donc deux appels avec un
/// filtre équivalent partagent le même cache.
final filteredPropertyExpensesProvider = Provider.autoDispose
    .family<
      AsyncValue<List<Expense>>,
      ({String propertyId, ExpenseFilter filter})
    >((ref, args) {
      final async = ref.watch(propertyExpensesProvider(args.propertyId));
      return async.whenData(args.filter.apply);
    });

/// Totaux récupérable / non-récupérable calculés à partir d'une liste de
/// dépenses (déjà filtrée le cas échéant) — logique pure, testable.
class ExpenseTotals {
  const ExpenseTotals({
    required this.recoverableCents,
    required this.nonRecoverableCents,
  });

  final int recoverableCents;
  final int nonRecoverableCents;

  int get totalCents => recoverableCents + nonRecoverableCents;

  factory ExpenseTotals.fromExpenses(Iterable<Expense> expenses) {
    var recoverable = 0;
    var nonRecoverable = 0;
    for (final e in expenses) {
      if (e.isRecoverable) {
        recoverable += e.amountCents;
      } else {
        nonRecoverable += e.amountCents;
      }
    }
    return ExpenseTotals(
      recoverableCents: recoverable,
      nonRecoverableCents: nonRecoverable,
    );
  }
}
