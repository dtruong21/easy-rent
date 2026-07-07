import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/expenses_repository.dart';
import '../domain/expense.dart';

final _log = Logger('ExpenseDetailProvider');

/// Provider qui charge une dépense par son [id].
///
/// Lance [ExpenseNotFoundException] si Firestore retourne 0 ligne (dépense
/// archivée, non possédée, ou id inconnu).
final expenseDetailProvider = FutureProvider.family<Expense, String>((
  ref,
  id,
) async {
  _log.info('fetch expense detail id=$id');
  return ref.read(expensesRepositoryProvider).getById(id);
});
