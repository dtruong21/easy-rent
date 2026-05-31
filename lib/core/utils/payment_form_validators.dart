import '../../features/payments/domain/payment_method.dart';
import 'date_bounds.dart';
import 'money_validators.dart';

/// Validateurs du formulaire paiement — logique pure, sans dépendance Flutter.
///
/// Délègue à [MoneyValidators] et [DateBounds] pour les règles partagées avec
/// FEAT-005 (baux). Reste responsable des règles spécifiques au paiement
/// (période début/fin, date d'encaissement, mode, notes).
class PaymentFormValidators {
  const PaymentFormValidators._();

  /// Valide la date de début de période.
  static String? validatePeriodStart(DateTime? value) {
    if (value == null) return 'La date de début de période est obligatoire';
    if (!DateBounds.contains(value)) {
      return 'Date invalide (année hors limites)';
    }
    return null;
  }

  /// Valide la date de fin de période.
  ///
  /// Doit être strictement postérieure à [start] si fournie.
  static String? validatePeriodEnd(DateTime? value, DateTime? start) {
    if (value == null) return 'La date de fin de période est obligatoire';
    if (!DateBounds.contains(value)) {
      return 'Date invalide (année hors limites)';
    }
    if (start != null && !value.isAfter(start)) {
      return 'La date de fin doit être postérieure à la date de début';
    }
    return null;
  }

  /// Valide la date de paiement effective.
  ///
  /// Note : une date dans le futur est autorisée (prélèvement programmé,
  /// cf. décision produit FEAT-006).
  static String? validatePaidAt(DateTime? value) {
    if (value == null) return 'La date de paiement est obligatoire';
    if (!DateBounds.contains(value)) {
      return 'Date invalide (année hors limites)';
    }
    return null;
  }

  /// Valide le montant du loyer hors charges (saisi en euros, string).
  static String? validateRentAmount(String? value) =>
      MoneyValidators.validateRentAmount(value);

  /// Valide le montant des charges (saisi en euros, string).
  static String? validateChargesAmount(String? value) =>
      MoneyValidators.validateChargesAmount(value);

  /// Valide le mode de paiement.
  static String? validatePaymentMethod(PaymentMethod? value) {
    if (value == null) return 'Le mode de paiement est obligatoire';
    return null;
  }

  /// Valide les notes (optionnelles, max 500 caractères).
  static String? validateNotes(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length > 500) {
      return 'Les notes ne peuvent pas dépasser 500 caractères';
    }
    return null;
  }
}
