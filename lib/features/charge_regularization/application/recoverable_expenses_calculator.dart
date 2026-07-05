/// Calcul des dépenses réelles récupérables sur une période de référence
/// (FEAT-041c — alimentation de la régularisation annuelle des charges,
/// bail nu).
///
/// Fonction pure, jumelle de [sumChargeProvisionsForPeriod]
/// (`charge_provisions_calculator.dart`) : reçoit une liste d'[Expense] déjà
/// chargées (via `ExpensesRepository.watchForProperty`, lecture client
/// existante) et une période de référence, retourne la somme des
/// `amountCents` des dépenses **récupérables** dont la période de
/// rattachement (`periodStart` → `periodEnd`) RECOUVRE (au moins
/// partiellement) la période de référence.
///
/// Garde-fou légal (décret n°87-713 du 26 août 1987) : ne somme **QUE**
/// `category == ExpenseCategory.recoverable` — une dépense `nonRecoverable`
/// (taxe foncière, assurance PNO, honoraires de gestion...) n'a jamais sa
/// place dans une régularisation de charges locatives, cf.
/// `charge_regularization_balance.dart` L42-45.
///
/// Piège de fuseau horaire (même pattern que `charge_provisions_calculator.
/// dart` et `lease_lateness.dart`, `_dateOnly`) : `periodStart`/`periodEnd`
/// d'une [Expense] relue depuis Firestore sont des `DateTime` UTC (écrits
/// `.toUtc().toIso8601String()`, relus via `firestoreDocToSnakeJson`).
/// Comparer directement ces instants UTC à une période de référence choisie
/// en heure LOCALE (date picker) décale les bornes d'un jour selon l'heure
/// de la journée. On applique donc systématiquement `.toLocal()` avant de
/// tronquer à `DateTime(y, m, d)`.
library;

import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_category.dart';

/// Somme des `amountCents` des [expenses] **récupérables**
/// (`category == ExpenseCategory.recoverable`) dont la période de
/// rattachement (`periodStart` → `periodEnd`) recouvre, au moins
/// partiellement, la période de référence `[referenceStart, referenceEnd]`
/// (bornes incluses).
///
/// Recouvrement d'intervalle : `expense.periodStart <= referenceEnd &&
/// expense.periodEnd >= referenceStart` — un seul jour de chevauchement
/// suffit à inclure la dépense en totalité (pas de proratisation
/// jour-par-jour, cohérent avec `sumChargeProvisionsForPeriod`).
///
/// Une dépense récupérable sans `periodStart`/`periodEnd` (ne devrait pas
/// arriver — `createExpense` les impose pour `category == recoverable`,
/// voir `docs/plans/FEAT-041-depenses.md` § a) est exclue défensivement
/// plutôt que de lever une exception : mieux vaut sous-compter que planter
/// l'écran de régularisation sur une donnée legacy/corrompue.
///
/// Filtre optionnel [leaseId] : si fourni, ne considère que les dépenses
/// dont `expense.leaseId == leaseId` — utile pour ventiler une régularisation
/// par bail sur un bien à plusieurs baux (colocation à baux multiples,
/// succession de baux dans l'année). Si `null` (défaut), toutes les dépenses
/// récupérables du bien sont sommées, y compris celles sans bail rattaché
/// (décompte syndic global).
int sumRecoverableExpensesForPeriod({
  required Iterable<Expense> expenses,
  required DateTime referenceStart,
  required DateTime referenceEnd,
  String? leaseId,
}) {
  final start = _dateOnly(referenceStart);
  final end = _dateOnly(referenceEnd);

  var total = 0;
  for (final expense in expenses) {
    if (expense.category != ExpenseCategory.recoverable) continue;
    if (leaseId != null && expense.leaseId != leaseId) continue;

    final periodStart = expense.periodStart;
    final periodEnd = expense.periodEnd;
    if (periodStart == null || periodEnd == null) continue;

    final expenseStart = _dateOnly(periodStart);
    final expenseEnd = _dateOnly(periodEnd);
    final overlaps = !expenseStart.isAfter(end) && !expenseEnd.isBefore(start);
    if (overlaps) {
      total += expense.amountCents;
    }
  }
  return total;
}

/// Tronque une [DateTime] à sa partie date CIVILE LOCALE (ignore l'heure).
///
/// Duplique intentionnellement `_dateOnly` de
/// `charge_provisions_calculator.dart` / `lease_lateness.dart` — fonction
/// privée dans les trois fichiers, extraction dans un helper partagé jugée
/// non justifiée pour une fonction de 3 lignes (même arbitrage que le
/// fichier jumeau).
DateTime _dateOnly(DateTime dt) {
  final local = dt.toLocal();
  return DateTime(local.year, local.month, local.day);
}
