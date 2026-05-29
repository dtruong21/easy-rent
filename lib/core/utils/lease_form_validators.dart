import '../../features/properties/domain/property.dart';
import '../../features/tenants/domain/tenant.dart';
import 'money_format.dart';

/// Validateurs du formulaire bail — logique pure, sans dépendance Flutter.
///
/// Testables unitairement sans mock. Même pattern que [TenantFormValidators]
/// et [PropertyFormValidators].
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
    // cents >= 0 déjà garanti par eurosToCents (retourne null si négatif)
    return null;
  }

  /// Valide la date de début.
  ///
  /// Règle : champ requis.
  static String? validateStartDate(DateTime? value) {
    if (value == null) return 'La date de début est obligatoire';
    return null;
  }

  /// Valide la date de fin (optionnelle).
  ///
  /// Si renseignée, doit être strictement postérieure à [startDate].
  static String? validateEndDate(DateTime? endDate, DateTime? startDate) {
    if (endDate == null) return null; // optionnelle — CDI si absente
    if (startDate == null) return null; // si start absente, pas de cross-check
    if (!endDate.isAfter(startDate)) {
      return 'La date de fin doit être postérieure à la date de début';
    }
    return null;
  }
}
