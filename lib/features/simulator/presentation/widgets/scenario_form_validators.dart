import '../../../../core/utils/money_format.dart';

/// Validateurs du formulaire simulateur d'investissement (FEAT-018).
///
/// Logique pure, aucune dépendance Flutter.
/// Miroir des CHECK constraints DB (`investment_scenarios`).
class ScenarioFormValidators {
  const ScenarioFormValidators._();

  static const int _kMaxAmountCents = 100000000000; // 1 milliard €
  static const int _kMaxRateBps = 3000; // 30 %
  static const int _kMinDurationMonths = 12;
  static const int _kMaxDurationMonths = 360;

  /// Nom du scénario : obligatoire, 1–120 caractères.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le nom du scénario est obligatoire';
    }
    if (value.trim().length > 120) {
      return 'Le nom ne peut pas dépasser 120 caractères';
    }
    return null;
  }

  /// Prix d'achat : obligatoire, strictement positif.
  static String? validatePurchasePrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le prix d\'achat est obligatoire';
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null || cents <= 0) {
      return 'Le prix d\'achat doit être positif';
    }
    if (cents > _kMaxAmountCents) {
      return 'Montant trop élevé';
    }
    return null;
  }

  /// Montant optionnel >= 0 (frais notaire, travaux, apport, capital, charges).
  static String? validateOptionalPositiveAmount(
    String? value, {
    String label = 'Ce montant',
  }) {
    if (value == null || value.trim().isEmpty) return null; // optionnel
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null) {
      return '$label ne peut pas être négatif';
    }
    if (cents > _kMaxAmountCents) {
      return 'Montant trop élevé';
    }
    return null;
  }

  /// Loyer mensuel HC : obligatoire, strictement positif.
  static String? validateMonthlyRent(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Le loyer mensuel HC est obligatoire';
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null || cents <= 0) {
      return 'Le loyer doit être positif';
    }
    if (cents > 500000000) {
      // 5 000 000 €
      return 'Montant trop élevé';
    }
    return null;
  }

  /// Taux nominal (optionnel) : 0–30 % en bps (0–3000).
  ///
  /// Saisie en % (ex. "3.5" = 3,5 % = 350 bps).
  static String? validateLoanRate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final cleaned = value.trim().replaceAll(',', '.');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed < 0) {
      return 'Le taux doit être compris entre 0 et 30 %';
    }
    final bps = (parsed * 100).round();
    if (bps > _kMaxRateBps) {
      return 'Le taux maximum est 30 %';
    }
    return null;
  }

  /// Durée (optionnel) : 12–360 mois.
  ///
  /// Saisie en mois (entier).
  static String? validateLoanDuration(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < _kMinDurationMonths) {
      return 'La durée minimale est 12 mois';
    }
    if (parsed > _kMaxDurationMonths) {
      return 'La durée maximale est 360 mois';
    }
    return null;
  }

  /// Notes (optionnel) : max 2000 caractères.
  static String? validateNotes(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.trim().length > 2000) {
      return 'Les notes ne peuvent pas dépasser 2000 caractères';
    }
    return null;
  }
}
