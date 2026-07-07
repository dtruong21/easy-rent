import '../validation/validation_error.dart';
import 'money_format.dart';

/// Validateurs de montants en euros — logique pure, sans dépendance Flutter.
///
/// Source unique pour la validation loyer/charges utilisée par les formulaires
/// bail (FEAT-005), paiement (FEAT-006) et à venir quittance (FEAT-007).
/// Aligné sur le plafond serveur Postgres.
///
/// FEAT-043 (i18n) : retourne un [ValidationError] (pur, sans `BuildContext`)
/// au lieu d'un message FR en dur — voir `lib/l10n/l10n_convention.dart`.
class MoneyValidators {
  const MoneyValidators._();

  /// Plafond absolu d'un montant en centimes.
  /// `100 000 000` cts = `1 000 000,00 €`. Bien sous le plafond int32 Postgres.
  static const int kMaxAmountCents = 100000000;

  /// Valide un montant de loyer hors charges (saisi en euros, string).
  ///
  /// Règle : champ requis, montant strictement positif, ≤ [kMaxAmountCents].
  static ValidationError? validateRentAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.rentRequired;
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null || cents <= 0) {
      return ValidationError.rentNotPositive;
    }
    if (cents > kMaxAmountCents) {
      return ValidationError.amountTooLargeWithCap;
    }
    return null;
  }

  /// Valide un montant de charges (saisi en euros, string).
  ///
  /// Règle : champ requis, montant ≥ 0 (0 accepté), ≤ [kMaxAmountCents].
  ///
  /// [requiredError] permet aux appelants dont le champ ne représente pas
  /// littéralement des « charges » (ex. dépenses réelles de régularisation,
  /// FEAT-029) de fournir un cas d'erreur adapté au contexte métier, sans
  /// dupliquer la logique de validation. Par défaut, conserve le cas
  /// historique utilisé par les formulaires bail/paiement.
  static ValidationError? validateChargesAmount(
    String? value, {
    ValidationError requiredError = ValidationError.chargesRequired,
  }) {
    if (value == null || value.trim().isEmpty) {
      return requiredError;
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null) {
      return ValidationError.chargesNegative;
    }
    // cents >= 0 déjà garanti par eurosToCents (retourne null si négatif).
    if (cents > kMaxAmountCents) {
      return ValidationError.amountTooLargeWithCap;
    }
    return null;
  }
}
