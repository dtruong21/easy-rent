import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/expenses_repository.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';
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

/// Paramètres de [recoverableExpensesProvider] — bien obligatoire, bail
/// optionnel (`null` = pas de filtre par bail).
///
/// Type record plutôt que classe dédiée : Riverpod compare les records par
/// valeur (`==` structurel natif Dart), donc deux appels avec les mêmes
/// `(propertyId, leaseId)` partagent le même cache sans codegen freezed
/// supplémentaire pour un simple couple de paramètres.
typedef RecoverableExpensesArgs = ({String propertyId, String? leaseId});

/// Stream des dépenses **récupérables** (FEAT-041c — alimentation de la
/// régularisation FEAT-029) d'un bien, filtrées optionnellement par bail.
///
/// Dérivé de [propertyExpensesProvider] (même stream sous-jacent, un seul
/// listener Firestore par bien) plutôt qu'une nouvelle requête dédiée — la
/// collection `expenses` n'expose pas d'index composite
/// `category + leaseId` qui justifierait une requête serveur séparée pour
/// ce volume (mono-bailleur, cf. `docs/plans/FEAT-041-depenses.md` § b).
final recoverableExpensesProvider = Provider.autoDispose
    .family<AsyncValue<List<Expense>>, RecoverableExpensesArgs>((ref, args) {
      final async = ref.watch(propertyExpensesProvider(args.propertyId));
      return async.whenData(
        (expenses) => expenses
            .where((e) => e.category == ExpenseCategory.recoverable)
            .where((e) => args.leaseId == null || e.leaseId == args.leaseId)
            .toList(),
      );
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
