import '../validation/validation_error.dart';
import 'date_bounds.dart';
import 'money_validators.dart';

/// Validateurs du formulaire dépense — logique pure, sans dépendance Flutter.
///
/// Délègue à [MoneyValidators]/[DateBounds] pour les règles partagées avec
/// FEAT-005/FEAT-006. Reste responsable des règles spécifiques à la dépense
/// (montant strictement positif, date de facture, période de rattachement
/// obligatoire si récupérable — décret n°87-713).
///
/// FEAT-043 (i18n) : retourne un [ValidationError] (pur, sans `BuildContext`)
/// au lieu d'un message FR en dur — voir `lib/l10n/l10n_convention.dart`.
class ExpenseFormValidators {
  const ExpenseFormValidators._();

  /// Valide le montant TTC de la dépense (saisi en euros, string).
  ///
  /// Règle : champ requis, montant strictement positif (`>= 1` centime).
  ///
  /// Délègue à [MoneyValidators.validateRentAmount] (mêmes bornes) en
  /// remappant les cas « loyer » vers les cas « montant » génériques — le
  /// champ dépense ne représente pas un loyer (équivalent du
  /// `.replaceFirst('Le loyer', 'Le montant')` de l'ancienne version FR).
  static ValidationError? validateAmount(String? value) {
    final rentError = MoneyValidators.validateRentAmount(value);
    return switch (rentError) {
      null => null,
      ValidationError.rentRequired => ValidationError.amountRequired,
      ValidationError.rentNotPositive => ValidationError.amountNotPositive,
      _ => rentError,
    };
  }

  /// Valide la date de la dépense (facture/décompte).
  static ValidationError? validateExpenseDate(DateTime? value) {
    if (value == null) return ValidationError.expenseDateRequired;
    if (!DateBounds.contains(value)) {
      return ValidationError.dateOutOfRange;
    }
    return null;
  }

  /// Valide le début de période de rattachement.
  ///
  /// Obligatoire uniquement si [isRecoverable] (décret n°87-713 : seules les
  /// dépenses récupérables sont agrégées en régularisation).
  static ValidationError? validatePeriodStart(
    DateTime? value, {
    required bool isRecoverable,
  }) {
    if (value == null) {
      return isRecoverable
          ? ValidationError.periodRequiredForRecoverable
          : null;
    }
    if (!DateBounds.contains(value)) {
      return ValidationError.dateOutOfRange;
    }
    return null;
  }

  /// Valide la fin de période de rattachement.
  ///
  /// Doit être strictement postérieure au début si les deux sont fournis.
  static ValidationError? validatePeriodEnd(
    DateTime? value,
    DateTime? start, {
    required bool isRecoverable,
  }) {
    if (value == null) {
      return isRecoverable
          ? ValidationError.periodRequiredForRecoverable
          : null;
    }
    if (!DateBounds.contains(value)) {
      return ValidationError.dateOutOfRange;
    }
    if (start != null && !value.isAfter(start)) {
      return ValidationError.periodEndBeforeStart;
    }
    return null;
  }

  /// Valide les notes (optionnelles, max 2000 caractères — cf. plan § a).
  static ValidationError? validateNotes(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length > 2000) {
      return ValidationError.expenseNotesTooLong;
    }
    return null;
  }
}
