/// Erreurs de validation génériques, indépendantes de la locale d'affichage.
///
/// **Pattern FEAT-043 (i18n)** : les validateurs (`lib/core/utils/
/// *_validators.dart`) sont des fonctions pures testées sans
/// `BuildContext` — ils ne doivent jamais dépendre d'`AppLocalizations`.
/// Un validateur qui a besoin d'exposer un message localisable retourne cet
/// enum ; la couche présentation (widget, qui a un `BuildContext`) le
/// traduit via l'extension `ValidationErrorL10n.message` (voir
/// `validation_error_l10n.dart`).
///
/// Un cas par message distinct. Quand plusieurs validateurs produisent
/// exactement le même texte (ex. bornes de dates communes à bail/paiement/
/// dépense), ils partagent le même cas — voir les commentaires de section
/// ci-dessous pour la provenance de chaque cas.
/// Voir aussi `lib/l10n/l10n_convention.dart` pour la convention de nommage
/// des clés ARB associées (préfixe `validation*`).
enum ValidationError {
  // ---------------------------------------------------------------------
  // Génériques (pilote foundation FEAT-043)
  // ---------------------------------------------------------------------

  /// Champ obligatoire laissé vide.
  required,

  /// Adresse email dont le format ne correspond pas à un email valide.
  invalidEmail,

  // ---------------------------------------------------------------------
  // Partagés entre plusieurs validateurs (texte identique)
  // ---------------------------------------------------------------------

  /// Date hors des bornes absolues acceptées (1900-01-01..2100-12-31).
  /// Partagé par les dates de bail, paiement et dépense.
  dateOutOfRange,

  /// Montant strictement supérieur au plafond, avec rappel du plafond en
  /// euros. Partagé par loyer, charges (bail/paiement) et charges non
  /// récupérables.
  amountTooLargeWithCap,

  /// Montant strictement supérieur au plafond, sans détail du plafond.
  /// Partagé par le dépôt de garantie et les honoraires d'agence (bail).
  amountTooLarge,

  /// Date de fin antérieure ou égale à la date de début. Partagé par le
  /// bail (`validateEndDate`) et le paiement (`validatePeriodEnd`).
  endDateBeforeStartDate,

  // ---------------------------------------------------------------------
  // MoneyValidators (lib/core/utils/money_validators.dart)
  // ---------------------------------------------------------------------

  /// Loyer laissé vide.
  rentRequired,

  /// Loyer nul ou négatif (doit être strictement positif).
  rentNotPositive,

  /// Charges laissées vides (message par défaut, bail/paiement).
  chargesRequired,

  /// Charges négatives (saisie non numérique ou < 0).
  chargesNegative,

  /// Dépenses réelles laissées vides — message dédié utilisé par le
  /// formulaire de régularisation de charges (surcharge de
  /// `MoneyValidators.validateChargesAmount`, le champ ne représente pas
  /// des « charges » au sens bail/paiement).
  actualExpensesRequired,

  // ---------------------------------------------------------------------
  // ExpenseFormValidators (lib/core/utils/expense_form_validators.dart)
  // ---------------------------------------------------------------------

  /// Montant de la dépense laissé vide.
  amountRequired,

  /// Montant de la dépense nul ou négatif.
  amountNotPositive,

  /// Date de la dépense laissée vide.
  expenseDateRequired,

  /// Période de rattachement obligatoire absente (dépense récupérable
  /// uniquement — décret n°87-713). Partagé début/fin de période.
  periodRequiredForRecoverable,

  /// Fin de période antérieure ou égale au début (dépense).
  periodEndBeforeStart,

  /// Notes de dépense au-delà de 2000 caractères. Texte identique réutilisé
  /// par `ScenarioFormValidators.validateNotes` (simulateur, même plafond).
  expenseNotesTooLong,

  // ---------------------------------------------------------------------
  // LeaseFormValidators (lib/core/utils/lease_form_validators.dart)
  // ---------------------------------------------------------------------

  /// Aucun bien sélectionné.
  propertyRequired,

  /// Aucun locataire sélectionné.
  tenantRequired,

  /// Date de début de bail laissée vide.
  startDateRequired,

  /// Dépôt de garantie négatif.
  depositNegative,

  /// Jour d'échéance laissé vide.
  paymentDayRequired,

  /// Jour d'échéance non numérique.
  paymentDayInvalid,

  /// Jour d'échéance hors plage 1..28.
  paymentDayOutOfRange,

  /// Valeur IRL non numérique.
  irlValueInvalid,

  /// Valeur IRL négative ou nulle.
  irlValueNotPositive,

  /// Valeur IRL supérieure ou égale à 10 000.
  irlValueTooHigh,

  /// Trimestre IRL de référence au format invalide (attendu `T1-2026`).
  irlQuarterInvalidFormat,

  /// Honoraires d'agence négatifs.
  agencyFeesNegative,

  /// Charges non récupérables négatives (FEAT-036).
  nonRecoverableChargesNegative,

  // ---------------------------------------------------------------------
  // PropertyFormValidators (lib/core/utils/property_form_validators.dart)
  // ---------------------------------------------------------------------

  /// Nom du bien laissé vide.
  propertyNameRequired,

  /// Adresse du bien laissée vide.
  propertyAddressRequired,

  /// Code postal invalide (5 chiffres attendus).
  postalCodeInvalid,

  /// Nombre de pièces hors plage 1..50.
  roomsInvalid,

  /// Nombre de chambres hors plage 0..50.
  bedroomsInvalid,

  /// Étage hors plage -5..200.
  floorInvalid,

  /// Année de construction hors plage 1700..(année courante + 1).
  /// Paramétré par `{maxYear}` — voir
  /// `PropertyFormValidators.maxConstructionYear` pour la source unique du
  /// calcul (utilisée à la fois par le validateur et le mapping l10n).
  constructionYearInvalid,

  /// Lettre de classe DPE hors A..G.
  dpeLetterInvalid,

  /// Valeur DPE hors plage 1..1999 kWh/m²/an.
  dpeValueInvalid,

  /// Lettre de classe GES hors A..G.
  gesLetterInvalid,

  /// Prix d'achat non entier positif.
  purchasePriceInvalid,

  /// Prix d'achat au-delà d'1 milliard d'euros.
  purchasePriceTooHigh,

  /// Frais de notaire négatifs.
  notaryFeesInvalid,

  /// Montant annuel (taxe foncière, assurance PNO, charges copro) négatif.
  annualAmountInvalid,

  /// Taux d'emprunt hors plage 0..30 %.
  loanRateInvalid,

  /// Durée d'emprunt hors plage 12..360 mois.
  loanDurationInvalid,

  /// Taux d'assurance emprunteur hors plage 0..2 %.
  insuranceRateInvalid,

  /// Capital emprunté non entier positif.
  loanPrincipalInvalid,

  // ---------------------------------------------------------------------
  // ProfileFormValidators (lib/core/utils/profile_form_validators.dart)
  // ---------------------------------------------------------------------

  /// Nom complet du bailleur laissé vide.
  fullNameRequired,

  /// Nom complet du bailleur trop court (< 2 caractères).
  fullNameTooShort,

  /// Nom complet du bailleur trop long (> 200 caractères).
  fullNameTooLong,

  /// Adresse du bailleur laissée vide.
  profileAddressRequired,

  /// Adresse du bailleur trop courte (< 5 caractères).
  profileAddressTooShort,

  /// Adresse du bailleur trop longue (> 500 caractères).
  profileAddressTooLong,

  /// Téléphone du bailleur au format invalide.
  phoneInvalid,

  // ---------------------------------------------------------------------
  // PaymentFormValidators (lib/core/utils/payment_form_validators.dart)
  // ---------------------------------------------------------------------

  /// Date de début de période de paiement laissée vide.
  periodStartRequired,

  /// Date de fin de période de paiement laissée vide.
  periodEndRequired,

  /// Date de paiement laissée vide.
  paidAtRequired,

  /// Mode de paiement non sélectionné.
  paymentMethodRequired,

  /// Notes de paiement au-delà de 500 caractères.
  paymentNotesTooLong,

  // ---------------------------------------------------------------------
  // TenantFormValidators (lib/core/utils/tenant_form_validators.dart)
  // ---------------------------------------------------------------------

  /// Prénom du locataire laissé vide.
  firstNameRequired,

  /// Nom du locataire laissé vide.
  lastNameRequired,

  /// Date de naissance antérieure à 1900.
  birthDateTooEarly,

  /// Locataire mineur (< 18 ans révolus).
  tenantMustBeAdult,

  /// Lieu de naissance au-delà de 100 caractères.
  birthPlaceTooLong,

  /// Nationalité au-delà de 60 caractères.
  nationalityTooLong,

  /// Profession au-delà de 100 caractères.
  professionTooLong,

  /// Employeur au-delà de 100 caractères.
  employerTooLong,

  /// Revenus mensuels hors plage acceptée.
  monthlyIncomeInvalid,

  /// Adresse précédente au-delà de 300 caractères.
  previousAddressTooLong,

  /// Nom du garant au-delà de 200 caractères.
  guarantorNameTooLong,

  /// Email du garant dont le format ne correspond pas à un email valide.
  invalidGuarantorEmail,

  /// Téléphone du garant au-delà de 30 caractères.
  guarantorPhoneTooLong,

  // ---------------------------------------------------------------------
  // SurfaceValidator (lib/core/utils/surface_validator.dart)
  // ---------------------------------------------------------------------

  /// Surface non numérique.
  surfaceInvalid,

  /// Surface nulle ou négative (doit être strictement positive).
  surfaceNotPositive,

  /// Surface au-delà de 9999,99 m².
  surfaceTooLarge,

  // ---------------------------------------------------------------------
  // ScenarioFormValidators (lib/features/simulator/presentation/widgets/
  // scenario_form_validators.dart)
  // ---------------------------------------------------------------------

  /// Nom du scénario laissé vide.
  scenarioNameRequired,

  /// Nom du scénario au-delà de 120 caractères.
  scenarioNameTooLong,

  /// Prix d'achat laissé vide.
  scenarioPurchasePriceRequired,

  /// Prix d'achat nul ou négatif.
  scenarioPurchasePriceNotPositive,

  /// Montant optionnel non numérique (frais notaire, travaux, apport,
  /// capital emprunté, taxe foncière, assurance PNO, charges de copropriété).
  /// Message générique — ne mentionne plus le nom du champ (FEAT-043 : l'ex.
  /// paramètre `label` de `validateOptionalPositiveAmount` était un FR en dur
  /// composé à l'appel, incompatible avec `ValidationErrorL10n.message`, qui
  /// ne prend qu'un `BuildContext`).
  amountNegative,

  /// Loyer mensuel HC laissé vide (simulateur).
  scenarioMonthlyRentRequired,

  /// Loyer mensuel HC nul ou négatif (simulateur).
  scenarioMonthlyRentNotPositive,

  /// Taux d'emprunt non numérique ou négatif (simulateur).
  scenarioLoanRateInvalid,

  /// Taux d'emprunt au-delà de 30 % (simulateur).
  scenarioLoanRateTooHigh,

  /// Durée d'emprunt en-dessous de 12 mois (simulateur).
  scenarioLoanDurationTooShort,

  /// Durée d'emprunt au-delà de 360 mois (simulateur).
  scenarioLoanDurationTooLong,
}
