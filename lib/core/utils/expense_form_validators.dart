import 'date_bounds.dart';
import 'money_validators.dart';

/// Validateurs du formulaire dépense — logique pure, sans dépendance Flutter.
///
/// Délègue à [MoneyValidators]/[DateBounds] pour les règles partagées avec
/// FEAT-005/FEAT-006. Reste responsable des règles spécifiques à la dépense
/// (montant strictement positif, date de facture, période de rattachement
/// obligatoire si récupérable — décret n°87-713).
class ExpenseFormValidators {
  const ExpenseFormValidators._();

  /// Valide le montant TTC de la dépense (saisi en euros, string).
  ///
  /// Règle : champ requis, montant strictement positif (`>= 1` centime).
  static String? validateAmount(String? value) =>
      MoneyValidators.validateRentAmount(
        value,
      )?.replaceFirst('Le loyer', 'Le montant');

  /// Valide la date de la dépense (facture/décompte).
  static String? validateExpenseDate(DateTime? value) {
    if (value == null) return 'La date de la dépense est obligatoire';
    if (!DateBounds.contains(value)) {
      return 'Date invalide (année hors limites)';
    }
    return null;
  }

  /// Valide le début de période de rattachement.
  ///
  /// Obligatoire uniquement si [isRecoverable] (décret n°87-713 : seules les
  /// dépenses récupérables sont agrégées en régularisation).
  static String? validatePeriodStart(
    DateTime? value, {
    required bool isRecoverable,
  }) {
    if (value == null) {
      return isRecoverable
          ? 'La période de rattachement est obligatoire pour une dépense '
                'récupérable'
          : null;
    }
    if (!DateBounds.contains(value)) {
      return 'Date invalide (année hors limites)';
    }
    return null;
  }

  /// Valide la fin de période de rattachement.
  ///
  /// Doit être strictement postérieure au début si les deux sont fournis.
  static String? validatePeriodEnd(
    DateTime? value,
    DateTime? start, {
    required bool isRecoverable,
  }) {
    if (value == null) {
      return isRecoverable
          ? 'La période de rattachement est obligatoire pour une dépense '
                'récupérable'
          : null;
    }
    if (!DateBounds.contains(value)) {
      return 'Date invalide (année hors limites)';
    }
    if (start != null && !value.isAfter(start)) {
      return 'La fin de période doit être postérieure au début';
    }
    return null;
  }

  /// Valide les notes (optionnelles, max 2000 caractères — cf. plan § a).
  static String? validateNotes(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length > 2000) {
      return 'Les notes ne peuvent pas dépasser 2000 caractères';
    }
    return null;
  }
}
