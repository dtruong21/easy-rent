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
}
