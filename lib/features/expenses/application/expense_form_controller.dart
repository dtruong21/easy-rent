import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../core/finance/expense_recurrence.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';
import '../domain/expense_form_state.dart';
import '../domain/expense_nature.dart';
import '../domain/expense_submit_error.dart';
import 'expenses_provider.dart';

final _log = Logger('ExpenseFormController');

/// Contrôle le formulaire de création / édition d'une dépense.
///
/// Distingue create ([initial] == null) et update ([initial] != null).
/// Sur succès : invalide [propertyExpensesProvider(propertyId)] pour que
/// l'historique et le résumé de la fiche bien soient à jour.
///
/// [documentId] (FEAT-041b) : transmis si un justificatif a été uploadé
/// avant la soumission (recommandé, non bloquant — cf.
/// `docs/plans/FEAT-041-depenses.md` § g).
///
/// Utilise [autoDispose] pour réinitialiser l'état entre deux ouvertures
/// du formulaire.
class ExpenseFormController extends StateNotifier<ExpenseFormState> {
  ExpenseFormController(this._ref) : super(const ExpenseFormState.idle());

  final Ref _ref;

  /// Soumet le formulaire (création ou édition).
  ///
  /// [initial] : null pour une création, dépense existante pour une édition.
  /// [propertyId] : id du bien parent (requis pour l'invalidation du cache).
  Future<void> submit({
    Expense? initial,
    required String propertyId,
    String? leaseId,
    required int amountCents,
    required DateTime expenseDate,
    required ExpenseNature nature,
    ExpenseCategory? category,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? periodYear,
    ExpenseRecurrence recurrence = ExpenseRecurrence.none,
    DateTime? recurrenceEndDate,
    String? documentId,
    String? notes,
  }) async {
    state = const ExpenseFormState.submitting();

    try {
      final repo = _ref.read(expensesRepositoryProvider);
      final Expense result;

      if (initial == null) {
        // Mode création.
        result = await repo.create(
          propertyId: propertyId,
          leaseId: leaseId,
          amountCents: amountCents,
          expenseDate: expenseDate,
          nature: nature,
          category: category,
          periodStart: periodStart,
          periodEnd: periodEnd,
          periodYear: periodYear,
          recurrence: recurrence,
          recurrenceEndDate: recurrenceEndDate,
          documentId: documentId,
          notes: notes,
        );
        _log.info('expense created id=${result.id}');
      } else {
        // Mode édition — on applique les modifications sur le modèle existant.
        final resolvedCategory = category ?? nature.defaultCategory;
        final updated = initial.copyWith(
          amountCents: amountCents,
          expenseDate: expenseDate,
          nature: nature,
          category: resolvedCategory,
          categoryOverridden: resolvedCategory != nature.defaultCategory,
          periodStart: periodStart,
          periodEnd: periodEnd,
          periodYear: periodYear ?? initial.periodYear,
          recurrence: recurrence,
          recurrenceEndDate: recurrenceEndDate,
          documentId: documentId ?? initial.documentId,
          notes: notes,
        );
        result = await repo.update(updated);
        _log.info('expense updated id=${result.id}');
      }

      // Invalider le stream pour afficher la nouvelle/modifiée dépense.
      _ref.invalidate(propertyExpensesProvider(propertyId));

      state = ExpenseFormState.success(expense: result);
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning('FirebaseFunctionsException lors de submit', e, st);
      state = ExpenseFormState.error(message: _mapFirebaseError(e).name);
    } on ExpenseNotFoundException catch (notFound, st) {
      _log.warning('ExpenseNotFoundException lors de submit', notFound, st);
      state = ExpenseFormState.error(message: ExpenseSubmitError.notFound.name);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de submit', e, st);
      state = ExpenseFormState.error(message: ExpenseSubmitError.unknown.name);
    }
  }

  /// Archive (soft-delete) une dépense via `softDeleteEntity`.
  Future<void> archive({
    required String expenseId,
    required String propertyId,
  }) async {
    state = const ExpenseFormState.submitting();

    try {
      await _ref.read(expensesRepositoryProvider).archive(expenseId);
      _ref.invalidate(propertyExpensesProvider(propertyId));
      state = const ExpenseFormState.idle();
    } on FirebaseFunctionsException catch (e, st) {
      _log.warning('FirebaseFunctionsException lors de archive', e, st);
      state = ExpenseFormState.error(message: _mapFirebaseError(e).name);
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de archive', e, st);
      state = ExpenseFormState.error(message: ExpenseSubmitError.unknown.name);
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après une erreur).
  void reset() => state = const ExpenseFormState.idle();

  ExpenseSubmitError _mapFirebaseError(FirebaseFunctionsException e) {
    final code = e.code;
    final message = e.message ?? '';
    if (message.contains('category_locked_for_nature')) {
      return ExpenseSubmitError.categoryLockedForNature;
    }
    if (code == 'permission-denied' || code == 'unauthenticated') {
      return ExpenseSubmitError.permissionDenied;
    }
    if (code == 'failed-precondition') {
      return ExpenseSubmitError.invalidFields;
    }
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return ExpenseSubmitError.serviceUnavailable;
    }
    return ExpenseSubmitError.saveFailed;
  }
}

/// Provider autoDispose du contrôleur de formulaire dépense.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final expenseFormControllerProvider =
    StateNotifierProvider.autoDispose<ExpenseFormController, ExpenseFormState>(
      (ref) => ExpenseFormController(ref),
    );
