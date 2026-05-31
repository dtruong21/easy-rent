import '../../features/payments/domain/payment_method.dart';
import 'money_format.dart';

/// Validateurs du formulaire paiement — logique pure, sans dépendance Flutter.
///
/// Testables unitairement sans mock. Même pattern que [LeaseFormValidators]
/// et [TenantFormValidators].
class PaymentFormValidators {
  const PaymentFormValidators._();

  /// Bornes absolues acceptées pour les dates de paiement.
  ///
  /// Identiques aux contraintes Postgres sur la table `payments`
  /// (CHECK BETWEEN '1900-01-01' AND '2100-12-31').
  static final DateTime _kMinDate = DateTime(1900);
  static final DateTime _kMaxDate = DateTime(2100, 12, 31);

  /// Plafond absolu d'un montant (loyer ou charges), en centimes.
  /// 100 000 000 cts = 1 000 000,00 € — bien sous le plafond int32 de Postgres.
  static const int _kMaxAmountCents = 100000000;

  /// Valide la date de début de période.
  ///
  /// Règle : champ requis, bornes 1900–2100.
  static String? validatePeriodStart(DateTime? value) {
    if (value == null) return 'La date de début de période est obligatoire';
    if (value.isBefore(_kMinDate) || value.isAfter(_kMaxDate)) {
      return 'Date invalide (année hors limites)';
    }
    return null;
  }

  /// Valide la date de fin de période.
  ///
  /// Règle : champ requis, > start, bornes 1900–2100.
  static String? validatePeriodEnd(DateTime? value, DateTime? start) {
    if (value == null) return 'La date de fin de période est obligatoire';
    if (value.isBefore(_kMinDate) || value.isAfter(_kMaxDate)) {
      return 'Date invalide (année hors limites)';
    }
    if (start != null && !value.isAfter(start)) {
      return 'La date de fin doit être postérieure à la date de début';
    }
    return null;
  }

  /// Valide la date de paiement.
  ///
  /// Règle : champ requis, bornes 1900–2100.
  /// Note : une date dans le futur est autorisée (prélèvement programmé).
  static String? validatePaidAt(DateTime? value) {
    if (value == null) return 'La date de paiement est obligatoire';
    if (value.isBefore(_kMinDate) || value.isAfter(_kMaxDate)) {
      return 'Date invalide (année hors limites)';
    }
    return null;
  }

  /// Valide le montant du loyer hors charges (saisi en euros, string).
  ///
  /// Règle : champ requis, montant > 0.
  static String? validateRentAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le loyer est obligatoire';
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null) {
      return 'Le loyer doit être un montant positif';
    }
    if (cents <= 0) {
      return 'Le loyer doit être un montant positif';
    }
    if (cents > _kMaxAmountCents) {
      return 'Montant trop élevé (maximum 1 000 000,00 €)';
    }
    return null;
  }

  /// Valide le montant des charges (saisi en euros, string).
  ///
  /// Règle : champ requis, montant ≥ 0 (0 accepté).
  static String? validateChargesAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Les charges sont obligatoires (saisir 0 si aucune charge)';
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null) {
      return 'Les charges ne peuvent pas être négatives';
    }
    if (cents > _kMaxAmountCents) {
      return 'Montant trop élevé (maximum 1 000 000,00 €)';
    }
    return null;
  }

  /// Valide le mode de paiement.
  ///
  /// Règle : champ requis.
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
