import 'money_format.dart';

/// Validateurs de montants en euros — logique pure, sans dépendance Flutter.
///
/// Source unique pour la validation loyer/charges utilisée par les formulaires
/// bail (FEAT-005), paiement (FEAT-006) et à venir quittance (FEAT-007).
/// Aligné sur le plafond serveur Postgres.
class MoneyValidators {
  const MoneyValidators._();

  /// Plafond absolu d'un montant en centimes.
  /// `100 000 000` cts = `1 000 000,00 €`. Bien sous le plafond int32 Postgres.
  static const int kMaxAmountCents = 100000000;

  /// Valide un montant de loyer hors charges (saisi en euros, string).
  ///
  /// Règle : champ requis, montant strictement positif, ≤ [kMaxAmountCents].
  static String? validateRentAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le loyer est obligatoire';
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null || cents <= 0) {
      return 'Le loyer doit être un montant positif';
    }
    if (cents > kMaxAmountCents) {
      return 'Montant trop élevé (maximum 1 000 000,00 €)';
    }
    return null;
  }

  /// Valide un montant de charges (saisi en euros, string).
  ///
  /// Règle : champ requis, montant ≥ 0 (0 accepté), ≤ [kMaxAmountCents].
  static String? validateChargesAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Les charges sont obligatoires (saisir 0 si aucune charge)';
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null) {
      return 'Les charges ne peuvent pas être négatives';
    }
    // cents >= 0 déjà garanti par eurosToCents (retourne null si négatif).
    if (cents > kMaxAmountCents) {
      return 'Montant trop élevé (maximum 1 000 000,00 €)';
    }
    return null;
  }
}
