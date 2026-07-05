import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/expenses_repository.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';
import '../domain/expense_form_state.dart';
import '../domain/expense_nature.dart';
import 'expenses_provider.dart';

final _log = Logger('ExpenseFormController');

/// Contrôle le formulaire de création / édition d'une dépense.
///
/// Distingue create ([initial] == null) et update ([initial] != null).
/// Sur succès : invalide [propertyExpensesProvider(propertyId)] pour que
/// l'historique et le résumé de la fiche bien soient à jour.
///
/// ⚠️ FEAT-041a : `documentId` n'est jamais transmis (upload justificatif =
/// FEAT-041b, hors périmètre de ce bloc).
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
      state = ExpenseFormState.error(message: _mapFirebaseError(e));
    } on ExpenseNotFoundException catch (notFound, st) {
      _log.warning('ExpenseNotFoundException lors de submit', notFound, st);
      state = const ExpenseFormState.error(
        message: 'Dépense introuvable. Elle a peut-être été archivée.',
      );
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de submit', e, st);
      state = const ExpenseFormState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
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
      state = ExpenseFormState.error(message: _mapFirebaseError(e));
    } catch (e, st) {
      _log.severe('Erreur inattendue lors de archive', e, st);
      state = const ExpenseFormState.error(
        message: 'Une erreur est survenue. Veuillez réessayer.',
      );
    }
  }

  /// Remet le formulaire à l'état initial (ex. : après une erreur).
  void reset() => state = const ExpenseFormState.idle();

  String _mapFirebaseError(FirebaseFunctionsException e) {
    final code = e.code;
    final message = e.message ?? '';
    if (message.contains('category_locked_for_nature')) {
      return 'Cette nature de dépense impose une catégorie non modifiable.';
    }
    if (code == 'permission-denied' || code == 'unauthenticated') {
      return 'Action non autorisée.';
    }
    if (code == 'failed-precondition') {
      return 'Opération impossible — vérifiez les champs saisis.';
    }
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return 'Service temporairement indisponible. Réessayez.';
    }
    return 'Erreur lors de la sauvegarde. Veuillez réessayer.';
  }
}

/// Provider autoDispose du contrôleur de formulaire dépense.
///
/// [autoDispose] garantit un state propre entre deux ouvertures du formulaire.
final expenseFormControllerProvider =
    StateNotifierProvider.autoDispose<ExpenseFormController, ExpenseFormState>(
      (ref) => ExpenseFormController(ref),
    );
