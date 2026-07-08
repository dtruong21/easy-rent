import '../../features/properties/domain/property.dart';
import '../../features/tenants/domain/tenant.dart';
import '../validation/validation_error.dart';
import 'date_bounds.dart';
import 'money_format.dart';
import 'money_validators.dart';

/// Validateurs du formulaire bail — logique pure, sans dépendance Flutter.
///
/// Testables unitairement sans mock. Délègue à [MoneyValidators] et
/// [DateBounds] pour les règles partagées avec FEAT-006 (paiements).
///
/// FEAT-043 (i18n) : retourne un [ValidationError] (pur, sans `BuildContext`)
/// au lieu d'un message FR en dur — voir `lib/l10n/l10n_convention.dart`.
class LeaseFormValidators {
  const LeaseFormValidators._();

  /// Valide que [property] est bien sélectionné.
  static ValidationError? validateProperty(Property? property) {
    if (property == null) return ValidationError.propertyRequired;
    return null;
  }

  /// Valide que [tenant] est bien sélectionné.
  static ValidationError? validateTenant(Tenant? tenant) {
    if (tenant == null) return ValidationError.tenantRequired;
    return null;
  }

  /// Valide le montant du loyer hors charges (saisi en euros, string).
  static ValidationError? validateRentAmount(String? value) =>
      MoneyValidators.validateRentAmount(value);

  /// Valide le montant des charges (saisi en euros, string).
  static ValidationError? validateChargesAmount(String? value) =>
      MoneyValidators.validateChargesAmount(value);

  /// Valide la date de début.
  ///
  /// Règle : champ requis, dans la plage [DateBounds.min, DateBounds.max].
  static ValidationError? validateStartDate(DateTime? value) {
    if (value == null) return ValidationError.startDateRequired;
    if (!DateBounds.contains(value)) {
      return ValidationError.dateOutOfRange;
    }
    return null;
  }

  /// Valide la date de fin (optionnelle).
  ///
  /// Si renseignée, doit être strictement postérieure à [startDate] et dans
  /// la plage [DateBounds.min, DateBounds.max].
  static ValidationError? validateEndDate(
    DateTime? endDate,
    DateTime? startDate,
  ) {
    if (endDate == null) return null; // optionnelle — CDI si absente
    if (!DateBounds.contains(endDate)) {
      return ValidationError.dateOutOfRange;
    }
    if (startDate == null) return null; // si start absente, pas de cross-check
    if (!endDate.isAfter(startDate)) {
      return ValidationError.endDateBeforeStartDate;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Phase 3 — nouveaux validateurs
  // ---------------------------------------------------------------------------

  /// Valide le dépôt de garantie en centimes (optionnel).
  ///
  /// Si renseigné : doit être entre 0 et 10 milliards de centimes (100 M €).
  static ValidationError? validateDepositCents(int? value) {
    if (value == null) return null; // optionnel
    if (value < 0) return ValidationError.depositNegative;
    if (value > 1000000000) {
      return ValidationError.amountTooLarge;
    }
    return null;
  }

  /// Valide le jour d'échéance (1..28).
  ///
  /// Accepte null ou vide → retourne erreur car le champ est requis lorsqu'il est affiché.
  static ValidationError? validatePaymentDay(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.paymentDayRequired;
    }
    final day = int.tryParse(value.trim());
    if (day == null) return ValidationError.paymentDayInvalid;
    if (day < 1 || day > 28) {
      return ValidationError.paymentDayOutOfRange;
    }
    return null;
  }

  /// Valide la valeur IRL (optionnelle, décimal).
  ///
  /// Si renseignée : doit être un double > 0 et < 10 000.
  static ValidationError? validateIrlValue(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optionnel
    final v = double.tryParse(value.trim().replaceAll(',', '.'));
    if (v == null) return ValidationError.irlValueInvalid;
    if (v <= 0) return ValidationError.irlValueNotPositive;
    if (v >= 10000) return ValidationError.irlValueTooHigh;
    return null;
  }

  /// Valide le trimestre IRL de référence (optionnel).
  ///
  /// Si renseigné : doit correspondre au format `T[1-4]-YYYY` (ex : `T1-2026`).
  static ValidationError? validateIrlQuarter(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optionnel
    final regex = RegExp(r'^T[1-4]-\d{4}$');
    if (!regex.hasMatch(value.trim())) {
      return ValidationError.irlQuarterInvalidFormat;
    }
    return null;
  }

  /// Valide les honoraires d'agence en centimes.
  ///
  /// Doit être entre 0 et 10 milliards de centimes (100 M €).
  static ValidationError? validateAgencyFees(int? value) {
    if (value == null) return null; // 0 par défaut
    if (value < 0) return ValidationError.agencyFeesNegative;
    if (value > 1000000000) {
      return ValidationError.amountTooLarge;
    }
    return null;
  }

  /// Valide les charges non récupérables (saisi en euros, string ;
  /// FEAT-036, optionnel — 0/vide accepté).
  ///
  /// ⚠️ Prend la String brute (pas un `int?` déjà converti) : une saisie
  /// négative comme `"-20"` fait échouer `MoneyFormat.eurosToCents` (qui
  /// retourne `null` pour tout montant négatif), donc valider un `int?`
  /// déjà converti ne peut JAMAIS détecter le cas négatif. Même piège évité
  /// par [MoneyValidators.validateChargesAmount] sur le champ récupérable
  /// voisin — on applique ici la même stratégie de conversion interne, avec
  /// un cas d'erreur dédié pour ne pas confondre les deux champs.
  static ValidationError? validateNonRecoverableCharges(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optionnel
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null) {
      return ValidationError.nonRecoverableChargesNegative;
    }
    if (cents > MoneyValidators.kMaxAmountCents) {
      return ValidationError.amountTooLargeWithCap;
    }
    return null;
  }
}
