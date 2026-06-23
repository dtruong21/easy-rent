import '../../features/properties/domain/property.dart';
import '../../features/tenants/domain/tenant.dart';
import 'date_bounds.dart';
import 'money_validators.dart';

/// Validateurs du formulaire bail — logique pure, sans dépendance Flutter.
///
/// Testables unitairement sans mock. Délègue à [MoneyValidators] et
/// [DateBounds] pour les règles partagées avec FEAT-006 (paiements).
class LeaseFormValidators {
  const LeaseFormValidators._();

  /// Valide que [property] est bien sélectionné.
  static String? validateProperty(Property? property) {
    if (property == null) return 'Veuillez sélectionner un bien';
    return null;
  }

  /// Valide que [tenant] est bien sélectionné.
  static String? validateTenant(Tenant? tenant) {
    if (tenant == null) return 'Veuillez sélectionner un locataire';
    return null;
  }

  /// Valide le montant du loyer hors charges (saisi en euros, string).
  static String? validateRentAmount(String? value) =>
      MoneyValidators.validateRentAmount(value);

  /// Valide le montant des charges (saisi en euros, string).
  static String? validateChargesAmount(String? value) =>
      MoneyValidators.validateChargesAmount(value);

  /// Valide la date de début.
  ///
  /// Règle : champ requis, dans la plage [DateBounds.min, DateBounds.max].
  static String? validateStartDate(DateTime? value) {
    if (value == null) return 'La date de début est obligatoire';
    if (!DateBounds.contains(value)) {
      return 'Date invalide (année hors limites)';
    }
    return null;
  }

  /// Valide la date de fin (optionnelle).
  ///
  /// Si renseignée, doit être strictement postérieure à [startDate] et dans
  /// la plage [DateBounds.min, DateBounds.max].
  static String? validateEndDate(DateTime? endDate, DateTime? startDate) {
    if (endDate == null) return null; // optionnelle — CDI si absente
    if (!DateBounds.contains(endDate)) {
      return 'Date invalide (année hors limites)';
    }
    if (startDate == null) return null; // si start absente, pas de cross-check
    if (!endDate.isAfter(startDate)) {
      return 'La date de fin doit être postérieure à la date de début';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Phase 3 — nouveaux validateurs
  // ---------------------------------------------------------------------------

  /// Valide le dépôt de garantie en centimes (optionnel).
  ///
  /// Si renseigné : doit être entre 0 et 10 milliards de centimes (100 M €).
  static String? validateDepositCents(int? value) {
    if (value == null) return null; // optionnel
    if (value < 0) return 'Le dépôt de garantie ne peut pas être négatif';
    if (value > 1000000000) {
      return 'Montant trop élevé';
    }
    return null;
  }

  /// Valide le jour d'échéance (1..28).
  ///
  /// Accepte null ou vide → retourne erreur car le champ est requis lorsqu'il est affiché.
  static String? validatePaymentDay(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le jour d\'échéance est obligatoire';
    }
    final day = int.tryParse(value.trim());
    if (day == null) return 'Valeur invalide';
    if (day < 1 || day > 28) {
      return 'Le jour doit être compris entre 1 et 28';
    }
    return null;
  }

  /// Valide la valeur IRL (optionnelle, décimal).
  ///
  /// Si renseignée : doit être un double > 0 et < 10 000.
  static String? validateIrlValue(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optionnel
    final v = double.tryParse(value.trim().replaceAll(',', '.'));
    if (v == null) return 'Valeur invalide (ex : 142.43)';
    if (v <= 0) return 'La valeur IRL doit être positive';
    if (v >= 10000) return 'La valeur IRL doit être inférieure à 10 000';
    return null;
  }

  /// Valide le trimestre IRL de référence (optionnel).
  ///
  /// Si renseigné : doit correspondre au format `T[1-4]-YYYY` (ex : `T1-2026`).
  static String? validateIrlQuarter(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optionnel
    final regex = RegExp(r'^T[1-4]-\d{4}$');
    if (!regex.hasMatch(value.trim())) {
      return 'Format attendu : T1-2026, T2-2026, etc.';
    }
    return null;
  }

  /// Valide les honoraires d'agence en centimes.
  ///
  /// Doit être entre 0 et 10 milliards de centimes (100 M €).
  static String? validateAgencyFees(int? value) {
    if (value == null) return null; // 0 par défaut
    if (value < 0) return 'Les honoraires ne peuvent pas être négatifs';
    if (value > 1000000000) {
      return 'Montant trop élevé';
    }
    return null;
  }
}
