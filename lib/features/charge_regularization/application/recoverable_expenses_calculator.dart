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
/// rattachement recouvre la période de référence — voir
/// [expenseOverlapsPeriod] pour la sémantique exacte du recouvrement (y
/// compris le cas défensif d'une dépense récupérable sans
/// `periodStart`/`periodEnd`).
///
/// Filtre optionnel [leaseId] : si fourni, ne considère que les dépenses
/// **rattachables à ce bail** au sens de [expenseAppliesToLease] — c'est-à-
/// dire soit rattachées explicitement à ce bail (`expense.leaseId ==
/// leaseId`), soit **non rattachées à aucun bail** (`expense.leaseId ==
/// null`).
///
/// Correctif review FEAT-041 (finding 2, MAJOR) : le cas d'usage principal de
/// la régularisation — le décompte syndic — n'a le plus souvent **aucun
/// bail rattaché** (une dépense d'immeuble ne connaît pas le locataire). Un
/// filtre strict `expense.leaseId == leaseId` excluait ces dépenses et
/// faisait remonter la régularisation à 0 € dans le cas nominal. On inclut
/// donc les dépenses sans bail ET celles du bail courant ; on exclut
/// uniquement celles rattachées à un **autre** bail (ventilation légitime sur
/// un bien à plusieurs baux — colocation à baux multiples, succession de
/// baux dans l'année).
///
/// Si `leaseId` est `null` (défaut), toutes les dépenses récupérables du bien
/// sont sommées, quel que soit leur rattachement (décompte syndic global,
/// tous baux confondus).
int sumRecoverableExpensesForPeriod({
  required Iterable<Expense> expenses,
  required DateTime referenceStart,
  required DateTime referenceEnd,
  String? leaseId,
}) {
  var total = 0;
  for (final expense in expenses) {
    if (expense.category != ExpenseCategory.recoverable) continue;
    if (!expenseAppliesToLease(expense, leaseId)) continue;
    if (!expenseOverlapsPeriod(expense, referenceStart, referenceEnd)) {
      continue;
    }
    total += expense.amountCents;
  }
  return total;
}

/// Filtre [expenses] pour ne conserver que celles **effectivement prises en
/// compte** par [sumRecoverableExpensesForPeriod] pour les mêmes paramètres —
/// même prédicat de catégorie, de rattachement bail et de recouvrement de
/// période.
///
/// Correctif review FEAT-041 (findings 1 & 7, MAJOR) : le détail affiché au
/// bailleur (compteur « N dépenses » + liste dépliable dans
/// `ChargeRegularizationForm`) doit porter EXACTEMENT sur les dépenses ayant
/// contribué à la somme pré-remplie — sinon le nombre et le détail divergent
/// silencieusement du total (ex. dépenses hors période visibles dans le
/// détail alors qu'elles ne comptent pas dans le total). Centraliser ce
/// filtre ici garantit que la somme et la liste appliquent toujours
/// exactement la même sémantique.
List<Expense> filterRecoverableExpensesForPeriod({
  required Iterable<Expense> expenses,
  required DateTime referenceStart,
  required DateTime referenceEnd,
  String? leaseId,
}) {
  return expenses
      .where((e) => e.category == ExpenseCategory.recoverable)
      .where((e) => expenseAppliesToLease(e, leaseId))
      .where((e) => expenseOverlapsPeriod(e, referenceStart, referenceEnd))
      .toList();
}

/// Vrai si [expense] doit être prise en compte pour une régularisation
/// ventilée sur [leaseId].
///
/// Sémantique (correctif review FEAT-041, finding 2) :
/// - `leaseId == null` → aucun filtre, toutes les dépenses s'appliquent.
/// - `leaseId != null` → s'applique si `expense.leaseId == leaseId` **ou**
///   `expense.leaseId == null` (dépense non rattachée, ex. décompte syndic
///   global) ; exclut les dépenses rattachées à un AUTRE bail.
bool expenseAppliesToLease(Expense expense, String? leaseId) {
  if (leaseId == null) return true;
  return expense.leaseId == null || expense.leaseId == leaseId;
}

/// Vrai si la période de rattachement de [expense]
/// (`periodStart` → `periodEnd`) recouvre, au moins partiellement, la période
/// de référence `[referenceStart, referenceEnd]` (bornes incluses).
///
/// Recouvrement d'intervalle : `expense.periodStart <= referenceEnd &&
/// expense.periodEnd >= referenceStart` — un seul jour de chevauchement
/// suffit à inclure la dépense en totalité (pas de proratisation
/// jour-par-jour, cohérent avec `sumChargeProvisionsForPeriod`).
///
/// Une dépense sans `periodStart`/`periodEnd` (ne devrait pas arriver —
/// `createExpense` les impose pour `category == recoverable`, voir
/// `docs/plans/FEAT-041-depenses.md` § a) est exclue défensivement plutôt que
/// de lever une exception : mieux vaut sous-compter que planter l'écran de
/// régularisation sur une donnée legacy/corrompue.
bool expenseOverlapsPeriod(
  Expense expense,
  DateTime referenceStart,
  DateTime referenceEnd,
) {
  final periodStart = expense.periodStart;
  final periodEnd = expense.periodEnd;
  if (periodStart == null || periodEnd == null) return false;

  final start = _dateOnly(referenceStart);
  final end = _dateOnly(referenceEnd);
  final expenseStart = _dateOnly(periodStart);
  final expenseEnd = _dateOnly(periodEnd);
  return !expenseStart.isAfter(end) && !expenseEnd.isBefore(start);
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
