import 'package:freezed_annotation/freezed_annotation.dart';

import 'expense.dart';

part 'expense_form_state.freezed.dart';

/// État UI du formulaire dépense.
///
/// Mêmes conventions que [PaymentFormState] :
/// - [idle] : formulaire prêt à la saisie.
/// - [submitting] : appel Callable en cours, bouton désactivé.
/// - [success] : opération réussie, contient la dépense créée/mise à jour.
/// - [error] : échec, message en français affiché inline.
@freezed
sealed class ExpenseFormState with _$ExpenseFormState {
  /// Formulaire au repos — prêt à recevoir une saisie.
  const factory ExpenseFormState.idle() = _Idle;

  /// Appel Callable en cours — bouton désactivé, indicateur affiché.
  const factory ExpenseFormState.submitting() = _Submitting;

  /// Opération réussie — contient la dépense créée ou mise à jour.
  const factory ExpenseFormState.success({required Expense expense}) = _Success;

  /// Erreur retournée par la Callable ou validation échouée.
  const factory ExpenseFormState.error({required String message}) = _Error;
}
