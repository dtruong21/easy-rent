import '../../features/payments/domain/payment_method.dart';
import '../validation/validation_error.dart';
import 'date_bounds.dart';
import 'money_validators.dart';

/// Validateurs du formulaire paiement — logique pure, sans dépendance Flutter.
///
/// Délègue à [MoneyValidators] et [DateBounds] pour les règles partagées avec
/// FEAT-005 (baux). Reste responsable des règles spécifiques au paiement
/// (période début/fin, date d'encaissement, mode, notes).
///
/// FEAT-043 (i18n) : retourne un [ValidationError] (pur, sans `BuildContext`)
/// au lieu d'un message FR en dur — voir `lib/l10n/l10n_convention.dart`.
class PaymentFormValidators {
  const PaymentFormValidators._();

  /// Valide la date de début de période.
  static ValidationError? validatePeriodStart(DateTime? value) {
    if (value == null) return ValidationError.periodStartRequired;
    if (!DateBounds.contains(value)) {
      return ValidationError.dateOutOfRange;
    }
    return null;
  }

  /// Valide la date de fin de période.
  ///
  /// Doit être strictement postérieure à [start] si fournie.
  static ValidationError? validatePeriodEnd(DateTime? value, DateTime? start) {
    if (value == null) return ValidationError.periodEndRequired;
    if (!DateBounds.contains(value)) {
      return ValidationError.dateOutOfRange;
    }
    if (start != null && !value.isAfter(start)) {
      return ValidationError.endDateBeforeStartDate;
    }
    return null;
  }

  /// Valide la date de paiement effective.
  ///
  /// Note : une date dans le futur est autorisée (prélèvement programmé,
  /// cf. décision produit FEAT-006).
  static ValidationError? validatePaidAt(DateTime? value) {
    if (value == null) return ValidationError.paidAtRequired;
    if (!DateBounds.contains(value)) {
      return ValidationError.dateOutOfRange;
    }
    return null;
  }

  /// Valide le montant du loyer hors charges (saisi en euros, string).
  static ValidationError? validateRentAmount(String? value) =>
      MoneyValidators.validateRentAmount(value);

  /// Valide le montant des charges (saisi en euros, string).
  static ValidationError? validateChargesAmount(String? value) =>
      MoneyValidators.validateChargesAmount(value);

  /// Valide le mode de paiement.
  static ValidationError? validatePaymentMethod(PaymentMethod? value) {
    if (value == null) return ValidationError.paymentMethodRequired;
    return null;
  }

  /// Valide les notes (optionnelles, max 500 caractères).
  static ValidationError? validateNotes(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length > 500) {
      return ValidationError.paymentNotesTooLong;
    }
    return null;
  }
}
