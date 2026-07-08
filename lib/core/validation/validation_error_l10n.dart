import 'package:flutter/widgets.dart';

import '../i18n/l10n_extensions.dart';
import '../utils/property_form_validators.dart';
import 'validation_error.dart';

/// Traduit un [ValidationError] en message localisé (FEAT-043).
///
/// Vit dans la couche présentation (a besoin d'un [BuildContext]) — le
/// domaine (`validation_error.dart`) reste pur. Voir
/// `lib/l10n/l10n_convention.dart` pour le pattern complet.
extension ValidationErrorL10n on ValidationError {
  String message(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      ValidationError.required => l10n.validationRequired,
      ValidationError.invalidEmail => l10n.validationInvalidEmail,

      ValidationError.dateOutOfRange => l10n.validationDateOutOfRange,
      ValidationError.amountTooLargeWithCap =>
        l10n.validationAmountTooLargeWithCap,
      ValidationError.amountTooLarge => l10n.validationAmountTooLarge,
      ValidationError.endDateBeforeStartDate =>
        l10n.validationEndDateBeforeStartDate,

      ValidationError.rentRequired => l10n.validationRentRequired,
      ValidationError.rentNotPositive => l10n.validationRentNotPositive,
      ValidationError.chargesRequired => l10n.validationChargesRequired,
      ValidationError.chargesNegative => l10n.validationChargesNegative,
      ValidationError.actualExpensesRequired =>
        l10n.validationActualExpensesRequired,

      ValidationError.amountRequired => l10n.validationAmountRequired,
      ValidationError.amountNotPositive => l10n.validationAmountNotPositive,
      ValidationError.expenseDateRequired => l10n.validationExpenseDateRequired,
      ValidationError.periodRequiredForRecoverable =>
        l10n.validationPeriodRequiredForRecoverable,
      ValidationError.periodEndBeforeStart =>
        l10n.validationPeriodEndBeforeStart,
      ValidationError.expenseNotesTooLong => l10n.validationExpenseNotesTooLong,

      ValidationError.propertyRequired => l10n.validationPropertyRequired,
      ValidationError.tenantRequired => l10n.validationTenantRequired,
      ValidationError.startDateRequired => l10n.validationStartDateRequired,
      ValidationError.depositNegative => l10n.validationDepositNegative,
      ValidationError.paymentDayRequired => l10n.validationPaymentDayRequired,
      ValidationError.paymentDayInvalid => l10n.validationPaymentDayInvalid,
      ValidationError.paymentDayOutOfRange =>
        l10n.validationPaymentDayOutOfRange,
      ValidationError.irlValueInvalid => l10n.validationIrlValueInvalid,
      ValidationError.irlValueNotPositive => l10n.validationIrlValueNotPositive,
      ValidationError.irlValueTooHigh => l10n.validationIrlValueTooHigh,
      ValidationError.irlQuarterInvalidFormat =>
        l10n.validationIrlQuarterInvalidFormat,
      ValidationError.agencyFeesNegative => l10n.validationAgencyFeesNegative,
      ValidationError.nonRecoverableChargesNegative =>
        l10n.validationNonRecoverableChargesNegative,

      ValidationError.propertyNameRequired =>
        l10n.validationPropertyNameRequired,
      ValidationError.propertyAddressRequired =>
        l10n.validationPropertyAddressRequired,
      ValidationError.postalCodeInvalid => l10n.validationPostalCodeInvalid,
      ValidationError.roomsInvalid => l10n.validationRoomsInvalid,
      ValidationError.bedroomsInvalid => l10n.validationBedroomsInvalid,
      ValidationError.floorInvalid => l10n.validationFloorInvalid,
      ValidationError.constructionYearInvalid =>
        l10n.validationConstructionYearInvalid(
          PropertyFormValidators.maxConstructionYear,
        ),
      ValidationError.dpeLetterInvalid => l10n.validationDpeLetterInvalid,
      ValidationError.dpeValueInvalid => l10n.validationDpeValueInvalid,
      ValidationError.gesLetterInvalid => l10n.validationGesLetterInvalid,
      ValidationError.purchasePriceInvalid =>
        l10n.validationPurchasePriceInvalid,
      ValidationError.purchasePriceTooHigh =>
        l10n.validationPurchasePriceTooHigh,
      ValidationError.notaryFeesInvalid => l10n.validationNotaryFeesInvalid,
      ValidationError.annualAmountInvalid => l10n.validationAnnualAmountInvalid,
      ValidationError.loanRateInvalid => l10n.validationLoanRateInvalid,
      ValidationError.loanDurationInvalid => l10n.validationLoanDurationInvalid,
      ValidationError.insuranceRateInvalid =>
        l10n.validationInsuranceRateInvalid,
      ValidationError.loanPrincipalInvalid =>
        l10n.validationLoanPrincipalInvalid,

      ValidationError.fullNameRequired => l10n.validationFullNameRequired,
      ValidationError.fullNameTooShort => l10n.validationFullNameTooShort,
      ValidationError.fullNameTooLong => l10n.validationFullNameTooLong,
      ValidationError.profileAddressRequired =>
        l10n.validationProfileAddressRequired,
      ValidationError.profileAddressTooShort =>
        l10n.validationProfileAddressTooShort,
      ValidationError.profileAddressTooLong =>
        l10n.validationProfileAddressTooLong,
      ValidationError.phoneInvalid => l10n.validationPhoneInvalid,

      ValidationError.periodStartRequired => l10n.validationPeriodStartRequired,
      ValidationError.periodEndRequired => l10n.validationPeriodEndRequired,
      ValidationError.paidAtRequired => l10n.validationPaidAtRequired,
      ValidationError.paymentMethodRequired =>
        l10n.validationPaymentMethodRequired,
      ValidationError.paymentNotesTooLong => l10n.validationPaymentNotesTooLong,

      ValidationError.firstNameRequired => l10n.validationFirstNameRequired,
      ValidationError.lastNameRequired => l10n.validationLastNameRequired,
      ValidationError.birthDateTooEarly => l10n.validationBirthDateTooEarly,
      ValidationError.tenantMustBeAdult => l10n.validationTenantMustBeAdult,
      ValidationError.birthPlaceTooLong => l10n.validationBirthPlaceTooLong,
      ValidationError.nationalityTooLong => l10n.validationNationalityTooLong,
      ValidationError.professionTooLong => l10n.validationProfessionTooLong,
      ValidationError.employerTooLong => l10n.validationEmployerTooLong,
      ValidationError.monthlyIncomeInvalid =>
        l10n.validationMonthlyIncomeInvalid,
      ValidationError.previousAddressTooLong =>
        l10n.validationPreviousAddressTooLong,
      ValidationError.guarantorNameTooLong =>
        l10n.validationGuarantorNameTooLong,
      ValidationError.invalidGuarantorEmail =>
        l10n.validationInvalidGuarantorEmail,
      ValidationError.guarantorPhoneTooLong =>
        l10n.validationGuarantorPhoneTooLong,

      ValidationError.surfaceInvalid => l10n.validationSurfaceInvalid,
      ValidationError.surfaceNotPositive => l10n.validationSurfaceNotPositive,
      ValidationError.surfaceTooLarge => l10n.validationSurfaceTooLarge,

      ValidationError.scenarioNameRequired =>
        l10n.validationScenarioNameRequired,
      ValidationError.scenarioNameTooLong => l10n.validationScenarioNameTooLong,
      ValidationError.scenarioPurchasePriceRequired =>
        l10n.validationScenarioPurchasePriceRequired,
      ValidationError.scenarioPurchasePriceNotPositive =>
        l10n.validationScenarioPurchasePriceNotPositive,
      ValidationError.amountNegative => l10n.validationAmountNegative,
      ValidationError.scenarioMonthlyRentRequired =>
        l10n.validationScenarioMonthlyRentRequired,
      ValidationError.scenarioMonthlyRentNotPositive =>
        l10n.validationScenarioMonthlyRentNotPositive,
      ValidationError.scenarioLoanRateInvalid =>
        l10n.validationScenarioLoanRateInvalid,
      ValidationError.scenarioLoanRateTooHigh =>
        l10n.validationScenarioLoanRateTooHigh,
      ValidationError.scenarioLoanDurationTooShort =>
        l10n.validationScenarioLoanDurationTooShort,
      ValidationError.scenarioLoanDurationTooLong =>
        l10n.validationScenarioLoanDurationTooLong,
    };
  }
}
