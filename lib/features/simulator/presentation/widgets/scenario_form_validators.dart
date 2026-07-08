import '../../../../core/utils/money_format.dart';
import '../../../../core/validation/validation_error.dart';

/// Validateurs du formulaire simulateur d'investissement (FEAT-018).
///
/// Logique pure, aucune dépendance Flutter/`BuildContext`. Miroir des CHECK
/// constraints DB (`investment_scenarios`).
///
/// **FEAT-043 (i18n)** : suit le pattern « validateur pur → [ValidationError]
/// → mapping l10n en présentation » établi par les autres `*_validators.dart`
/// (cf. `lib/l10n/l10n_convention.dart` §5) — retourne un [ValidationError]?
/// au lieu d'un `String?` FR en dur. La couche présentation (widgets
/// `simulator_page.dart`/`save_scenario_dialog.dart`, qui ont un
/// `BuildContext`) traduit via `ValidationErrorL10n.message(context)`.
class ScenarioFormValidators {
  const ScenarioFormValidators._();

  static const int _kMaxAmountCents = 100000000000; // 1 milliard €
  static const int _kMaxRateBps = 3000; // 30 %
  static const int _kMinDurationMonths = 12;
  static const int _kMaxDurationMonths = 360;

  /// Nom du scénario : obligatoire, 1–120 caractères.
  static ValidationError? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.scenarioNameRequired;
    }
    if (value.trim().length > 120) {
      return ValidationError.scenarioNameTooLong;
    }
    return null;
  }

  /// Prix d'achat : obligatoire, strictement positif.
  static ValidationError? validatePurchasePrice(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.scenarioPurchasePriceRequired;
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null || cents <= 0) {
      return ValidationError.scenarioPurchasePriceNotPositive;
    }
    if (cents > _kMaxAmountCents) {
      return ValidationError.amountTooLarge;
    }
    return null;
  }

  /// Montant optionnel >= 0 (frais notaire, travaux, apport, capital, charges).
  ///
  /// Message générique (FEAT-043) : ne mentionne plus le nom du champ (l'ex.
  /// paramètre `label`, FR en dur composé à l'appel — supprimé, cf.
  /// [ValidationError.amountNegative] pour le détail).
  static ValidationError? validateOptionalPositiveAmount(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optionnel
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null) {
      return ValidationError.amountNegative;
    }
    if (cents > _kMaxAmountCents) {
      return ValidationError.amountTooLarge;
    }
    return null;
  }

  /// Loyer mensuel HC : obligatoire, strictement positif.
  static ValidationError? validateMonthlyRent(String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError.scenarioMonthlyRentRequired;
    }
    final cents = MoneyFormat.eurosToCents(value);
    if (cents == null || cents <= 0) {
      return ValidationError.scenarioMonthlyRentNotPositive;
    }
    if (cents > 500000000) {
      // 5 000 000 €
      return ValidationError.amountTooLarge;
    }
    return null;
  }

  /// Taux nominal (optionnel) : 0–30 % en bps (0–3000).
  ///
  /// Saisie en % (ex. "3.5" = 3,5 % = 350 bps).
  static ValidationError? validateLoanRate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final cleaned = value.trim().replaceAll(',', '.');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed < 0) {
      return ValidationError.scenarioLoanRateInvalid;
    }
    final bps = (parsed * 100).round();
    if (bps > _kMaxRateBps) {
      return ValidationError.scenarioLoanRateTooHigh;
    }
    return null;
  }

  /// Durée (optionnel) : 12–360 mois.
  ///
  /// Saisie en mois (entier).
  static ValidationError? validateLoanDuration(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < _kMinDurationMonths) {
      return ValidationError.scenarioLoanDurationTooShort;
    }
    if (parsed > _kMaxDurationMonths) {
      return ValidationError.scenarioLoanDurationTooLong;
    }
    return null;
  }

  /// Notes (optionnel) : max 2000 caractères.
  static ValidationError? validateNotes(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.trim().length > 2000) {
      // Texte identique à ExpenseFormValidators — cas partagé.
      return ValidationError.expenseNotesTooLong;
    }
    return null;
  }
}
