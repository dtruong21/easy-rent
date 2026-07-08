import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/property_form_validators.dart';
import '../../../../core/utils/surface_validator.dart';
import '../../../../core/validation/validation_error_l10n.dart';
import '../../domain/heating_type.dart';
import '../../domain/property_type.dart';
import 'heating_type_l10n.dart';
import 'property_type_l10n.dart';

// Helpers de conversion texte → centimes et taux → basis points.
int? _eurosToCents(String text) {
  final raw = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (raw.isEmpty) return null;
  final d = double.tryParse(raw);
  if (d == null) return null;
  return (d * 100).round();
}

int? _percentToBps(String text) {
  final raw = text.trim().replaceAll(',', '.');
  if (raw.isEmpty) return null;
  final d = double.tryParse(raw);
  if (d == null) return null;
  return (d * 100).round();
}

/// Champs partagés du formulaire bien immobilier.
///
/// Organisé en 3 sections :
/// 1. Informations principales (obligatoires) : nom, adresse, type, surface,
///    code postal, ville.
/// 2. Caractéristiques (ExpansionTile optionnel) : pièces, chambres, étage,
///    ascenseur, meublé, chauffage, année de construction.
/// 3. DPE / GES (ExpansionTile optionnel) : classe DPE, valeur DPE, classe GES.
///
/// Utilisé dans [PropertyFormPage] pour la création et l'édition.
/// Utiliser un [GlobalKey<PropertyFormWidgetState>] pour appeler [validateAll].
class PropertyForm extends StatefulWidget {
  const PropertyForm({
    super.key,
    required this.formKey,
    required this.nameController,
    required this.addressController,
    required this.surfaceController,
    required this.postalCodeController,
    required this.cityController,
    required this.roomsController,
    required this.bedroomsController,
    required this.floorController,
    required this.constructionYearController,
    required this.dpeValueController,
    required this.selectedType,
    required this.onTypeChanged,
    required this.hasElevator,
    required this.onHasElevatorChanged,
    required this.furnished,
    required this.onFurnishedChanged,
    required this.selectedHeatingType,
    required this.onHeatingTypeChanged,
    required this.selectedDpeLetter,
    required this.onDpeLetterChanged,
    required this.selectedGesLetter,
    required this.onGesLetterChanged,
    this.enabled = true,
    // FEAT-017 — Financement & acquisition
    required this.purchasePriceController,
    required this.notaryFeesController,
    required this.propertyTaxController,
    required this.insurancePnoController,
    required this.condoFeesController,
    required this.loanPrincipalController,
    required this.loanRateController,
    required this.loanInsuranceRateController,
    required this.loanDurationController,
    required this.loanPaymentOverrideController,
    required this.isNewProperty,
    required this.onIsNewPropertyChanged,
    required this.purchaseDate,
    required this.onPurchaseDateChanged,
    required this.loanStartDate,
    required this.onLoanStartDateChanged,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController surfaceController;
  final TextEditingController postalCodeController;
  final TextEditingController cityController;
  final TextEditingController roomsController;
  final TextEditingController bedroomsController;
  final TextEditingController floorController;
  final TextEditingController constructionYearController;
  final TextEditingController dpeValueController;
  final PropertyType? selectedType;
  final ValueChanged<PropertyType?> onTypeChanged;
  final bool hasElevator;
  final ValueChanged<bool> onHasElevatorChanged;
  final bool furnished;
  final ValueChanged<bool> onFurnishedChanged;
  final HeatingType? selectedHeatingType;
  final ValueChanged<HeatingType?> onHeatingTypeChanged;
  final String? selectedDpeLetter;
  final ValueChanged<String?> onDpeLetterChanged;
  final String? selectedGesLetter;
  final ValueChanged<String?> onGesLetterChanged;
  final bool enabled;
  // FEAT-017 — Financement & acquisition
  final TextEditingController purchasePriceController;
  final TextEditingController notaryFeesController;
  final TextEditingController propertyTaxController;
  final TextEditingController insurancePnoController;
  final TextEditingController condoFeesController;
  final TextEditingController loanPrincipalController;
  final TextEditingController loanRateController;
  final TextEditingController loanInsuranceRateController;
  final TextEditingController loanDurationController;
  final TextEditingController loanPaymentOverrideController;
  final bool isNewProperty;
  final ValueChanged<bool> onIsNewPropertyChanged;
  final DateTime? purchaseDate;
  final ValueChanged<DateTime?> onPurchaseDateChanged;
  final DateTime? loanStartDate;
  final ValueChanged<DateTime?> onLoanStartDateChanged;

  @override
  State<PropertyForm> createState() => PropertyFormWidgetState();
}

/// State public de [PropertyForm] — exposé pour accès via [GlobalKey].
class PropertyFormWidgetState extends State<PropertyForm> {
  bool _nameTouched = false;
  bool _addressTouched = false;
  bool _surfaceTouched = false;
  bool _postalCodeTouched = false;
  bool _roomsTouched = false;
  bool _bedroomsTouched = false;
  bool _floorTouched = false;
  bool _constructionYearTouched = false;
  bool _dpeValueTouched = false;
  // FEAT-017 touched states
  bool _purchasePriceTouched = false;
  bool _notaryFeesTouched = false;
  bool _propertyTaxTouched = false;
  bool _insurancePnoTouched = false;
  bool _condoFeesTouched = false;
  bool _loanPrincipalTouched = false;
  bool _loanRateTouched = false;
  bool _loanInsuranceRateTouched = false;
  bool _loanDurationTouched = false;
  bool _loanPaymentOverrideTouched = false;

  static const List<String> _dpeGesLetters = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----------------------------------------------------------------
          // Section 1 — Informations principales
          // ----------------------------------------------------------------
          _SectionHeader(title: l10n.propertiesFormSectionMainInfo),
          const SizedBox(height: 12),

          // Nom du bien
          TextFormField(
            key: const Key('field_name'),
            controller: widget.nameController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormNameLabel,
              hintText: l10n.propertiesFormNameHint,
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_nameTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _nameTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_nameTouched) return null;
              return PropertyFormValidators.validateName(v)?.message(context);
            },
          ),
          const SizedBox(height: 16),

          // Adresse complète
          TextFormField(
            key: const Key('field_address'),
            controller: widget.addressController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormAddressLabel,
              hintText: l10n.propertiesFormAddressHint,
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_addressTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _addressTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_addressTouched) return null;
              return PropertyFormValidators.validateAddress(
                v,
              )?.message(context);
            },
          ),
          const SizedBox(height: 16),

          // Code postal + Ville (en ligne)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: TextFormField(
                  key: const Key('field_postal_code'),
                  controller: widget.postalCodeController,
                  enabled: widget.enabled,
                  decoration: InputDecoration(
                    labelText: l10n.propertiesFormPostalCodeLabel,
                    hintText: '75001',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  onChanged: (_) {
                    if (_postalCodeTouched) setState(() {});
                  },
                  onEditingComplete: () {
                    setState(() => _postalCodeTouched = true);
                    FocusScope.of(context).nextFocus();
                  },
                  validator: (v) {
                    if (!_postalCodeTouched) return null;
                    return PropertyFormValidators.validatePostalCode(
                      v,
                    )?.message(context);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('field_city'),
                  controller: widget.cityController,
                  enabled: widget.enabled,
                  decoration: InputDecoration(
                    labelText: l10n.propertiesFormCityLabel,
                    hintText: 'Paris',
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onEditingComplete: () {
                    FocusScope.of(context).nextFocus();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Type de bien (dropdown)
          DropdownButtonFormField<PropertyType>(
            key: const Key('field_type'),
            initialValue: widget.selectedType,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormTypeLabel,
              border: const OutlineInputBorder(),
            ),
            items: PropertyType.values
                .map(
                  (t) =>
                      DropdownMenuItem(value: t, child: Text(t.label(context))),
                )
                .toList(),
            onChanged: widget.enabled ? widget.onTypeChanged : null,
            validator: (v) =>
                v == null ? l10n.propertiesFormTypeRequired : null,
          ),
          const SizedBox(height: 16),

          // Surface (optionnelle)
          TextFormField(
            key: const Key('field_surface'),
            controller: widget.surfaceController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormSurfaceLabel,
              hintText: 'Ex. : 45,5',
              suffixText: 'm²',
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_surfaceTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _surfaceTouched = true);
            },
            validator: (v) {
              if (!_surfaceTouched) return null;
              return SurfaceValidator.validate(v)?.message(context);
            },
          ),

          const SizedBox(height: 24),

          // ----------------------------------------------------------------
          // Section 2 — Caractéristiques (optionnel, ExpansionTile)
          // ----------------------------------------------------------------
          _CaracteristiquesSection(
            roomsController: widget.roomsController,
            bedroomsController: widget.bedroomsController,
            floorController: widget.floorController,
            constructionYearController: widget.constructionYearController,
            hasElevator: widget.hasElevator,
            onHasElevatorChanged: widget.onHasElevatorChanged,
            furnished: widget.furnished,
            onFurnishedChanged: widget.onFurnishedChanged,
            selectedHeatingType: widget.selectedHeatingType,
            onHeatingTypeChanged: widget.onHeatingTypeChanged,
            enabled: widget.enabled,
            roomsTouched: _roomsTouched,
            bedroomsTouched: _bedroomsTouched,
            floorTouched: _floorTouched,
            constructionYearTouched: _constructionYearTouched,
            onRoomsTouched: () => setState(() => _roomsTouched = true),
            onBedroomsTouched: () => setState(() => _bedroomsTouched = true),
            onFloorTouched: () => setState(() => _floorTouched = true),
            onConstructionYearTouched: () =>
                setState(() => _constructionYearTouched = true),
          ),

          const SizedBox(height: 16),

          // ----------------------------------------------------------------
          // Section Financement & acquisition (optionnel, ExpansionTile)
          // ----------------------------------------------------------------
          _FinancementSection(
            purchasePriceController: widget.purchasePriceController,
            notaryFeesController: widget.notaryFeesController,
            propertyTaxController: widget.propertyTaxController,
            insurancePnoController: widget.insurancePnoController,
            condoFeesController: widget.condoFeesController,
            loanPrincipalController: widget.loanPrincipalController,
            loanRateController: widget.loanRateController,
            loanInsuranceRateController: widget.loanInsuranceRateController,
            loanDurationController: widget.loanDurationController,
            loanPaymentOverrideController: widget.loanPaymentOverrideController,
            isNewProperty: widget.isNewProperty,
            onIsNewPropertyChanged: widget.onIsNewPropertyChanged,
            purchaseDate: widget.purchaseDate,
            onPurchaseDateChanged: widget.onPurchaseDateChanged,
            loanStartDate: widget.loanStartDate,
            onLoanStartDateChanged: widget.onLoanStartDateChanged,
            enabled: widget.enabled,
            purchasePriceTouched: _purchasePriceTouched,
            notaryFeesTouched: _notaryFeesTouched,
            propertyTaxTouched: _propertyTaxTouched,
            insurancePnoTouched: _insurancePnoTouched,
            condoFeesTouched: _condoFeesTouched,
            loanPrincipalTouched: _loanPrincipalTouched,
            loanRateTouched: _loanRateTouched,
            loanInsuranceRateTouched: _loanInsuranceRateTouched,
            loanDurationTouched: _loanDurationTouched,
            loanPaymentOverrideTouched: _loanPaymentOverrideTouched,
            onPurchasePriceTouched: () =>
                setState(() => _purchasePriceTouched = true),
            onNotaryFeesTouched: () =>
                setState(() => _notaryFeesTouched = true),
            onPropertyTaxTouched: () =>
                setState(() => _propertyTaxTouched = true),
            onInsurancePnoTouched: () =>
                setState(() => _insurancePnoTouched = true),
            onCondoFeesTouched: () => setState(() => _condoFeesTouched = true),
            onLoanPrincipalTouched: () =>
                setState(() => _loanPrincipalTouched = true),
            onLoanRateTouched: () => setState(() => _loanRateTouched = true),
            onLoanInsuranceRateTouched: () =>
                setState(() => _loanInsuranceRateTouched = true),
            onLoanDurationTouched: () =>
                setState(() => _loanDurationTouched = true),
            onLoanPaymentOverrideTouched: () =>
                setState(() => _loanPaymentOverrideTouched = true),
          ),

          const SizedBox(height: 16),

          // ----------------------------------------------------------------
          // Section DPE / GES (optionnel, ExpansionTile)
          // ----------------------------------------------------------------
          _DpeSection(
            dpeValueController: widget.dpeValueController,
            selectedDpeLetter: widget.selectedDpeLetter,
            onDpeLetterChanged: widget.onDpeLetterChanged,
            selectedGesLetter: widget.selectedGesLetter,
            onGesLetterChanged: widget.onGesLetterChanged,
            enabled: widget.enabled,
            dpeValueTouched: _dpeValueTouched,
            onDpeValueTouched: () => setState(() => _dpeValueTouched = true),
            dpeGesLetters: _dpeGesLetters,
          ),
        ],
      ),
    );
  }

  /// Marque tous les champs comme "touchés" et valide le formulaire.
  ///
  /// Appelé par [PropertyFormPage] lors du tap sur "Soumettre".
  bool validateAll() {
    setState(() {
      _nameTouched = true;
      _addressTouched = true;
      _surfaceTouched = true;
      _postalCodeTouched = true;
      _roomsTouched = true;
      _bedroomsTouched = true;
      _floorTouched = true;
      _constructionYearTouched = true;
      _dpeValueTouched = true;
      _purchasePriceTouched = true;
      _notaryFeesTouched = true;
      _propertyTaxTouched = true;
      _insurancePnoTouched = true;
      _condoFeesTouched = true;
      _loanPrincipalTouched = true;
      _loanRateTouched = true;
      _loanInsuranceRateTouched = true;
      _loanDurationTouched = true;
      _loanPaymentOverrideTouched = true;
    });
    return widget.formKey.currentState?.validate() ?? false;
  }

  /// Extrait les données FEAT-017 depuis les contrôleurs.
  ///
  /// Retourne une map avec les valeurs en centimes/bps, ou null si non renseignées.
  Map<String, dynamic> extractFinancialData() {
    return {
      'purchasePriceCents': _eurosToCents(widget.purchasePriceController.text),
      'notaryFeesCents': _eurosToCents(widget.notaryFeesController.text),
      'propertyTaxAnnualCents': _eurosToCents(
        widget.propertyTaxController.text,
      ),
      'insurancePnoAnnualCents': _eurosToCents(
        widget.insurancePnoController.text,
      ),
      'condoFeesNonRecoverableCents': _eurosToCents(
        widget.condoFeesController.text,
      ),
      'loanPrincipalCents': _eurosToCents(widget.loanPrincipalController.text),
      'loanRateBps': _percentToBps(widget.loanRateController.text),
      'loanInsuranceBps': _percentToBps(
        widget.loanInsuranceRateController.text,
      ),
      'loanDurationMonths': int.tryParse(
        widget.loanDurationController.text.trim(),
      ),
      'loanMonthlyPaymentOverrideCents': _eurosToCents(
        widget.loanPaymentOverrideController.text,
      ),
      'isNewProperty': widget.isNewProperty,
      'purchaseDate': widget.purchaseDate,
      'loanStartDate': widget.loanStartDate,
    };
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 2 — Caractéristiques (ExpansionTile)
// ---------------------------------------------------------------------------

class _CaracteristiquesSection extends StatelessWidget {
  const _CaracteristiquesSection({
    required this.roomsController,
    required this.bedroomsController,
    required this.floorController,
    required this.constructionYearController,
    required this.hasElevator,
    required this.onHasElevatorChanged,
    required this.furnished,
    required this.onFurnishedChanged,
    required this.selectedHeatingType,
    required this.onHeatingTypeChanged,
    required this.enabled,
    required this.roomsTouched,
    required this.bedroomsTouched,
    required this.floorTouched,
    required this.constructionYearTouched,
    required this.onRoomsTouched,
    required this.onBedroomsTouched,
    required this.onFloorTouched,
    required this.onConstructionYearTouched,
  });

  final TextEditingController roomsController;
  final TextEditingController bedroomsController;
  final TextEditingController floorController;
  final TextEditingController constructionYearController;
  final bool hasElevator;
  final ValueChanged<bool> onHasElevatorChanged;
  final bool furnished;
  final ValueChanged<bool> onFurnishedChanged;
  final HeatingType? selectedHeatingType;
  final ValueChanged<HeatingType?> onHeatingTypeChanged;
  final bool enabled;
  final bool roomsTouched;
  final bool bedroomsTouched;
  final bool floorTouched;
  final bool constructionYearTouched;
  final VoidCallback onRoomsTouched;
  final VoidCallback onBedroomsTouched;
  final VoidCallback onFloorTouched;
  final VoidCallback onConstructionYearTouched;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Theme(
      // Supprime le trait de séparation par défaut de l'ExpansionTile.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('section_caracteristiques'),
        title: Text(l10n.propertiesFormSectionCharacteristics),
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        children: [
          // Pièces + Chambres
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('field_rooms'),
                  controller: roomsController,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: l10n.propertiesFormRoomsLabel,
                    hintText: 'Ex. : 3',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onEditingComplete: () {
                    onRoomsTouched();
                    FocusScope.of(context).nextFocus();
                  },
                  validator: (v) {
                    if (!roomsTouched) return null;
                    return PropertyFormValidators.validateRooms(
                      v,
                    )?.message(context);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('field_bedrooms'),
                  controller: bedroomsController,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: l10n.propertiesFormBedroomsLabel,
                    hintText: 'Ex. : 2',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onEditingComplete: () {
                    onBedroomsTouched();
                    FocusScope.of(context).nextFocus();
                  },
                  validator: (v) {
                    if (!bedroomsTouched) return null;
                    return PropertyFormValidators.validateBedrooms(
                      v,
                    )?.message(context);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Étage
          TextFormField(
            key: const Key('field_floor'),
            controller: floorController,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormFloorLabel,
              hintText: '0',
              helperText: l10n.propertiesFormFloorHelper,
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            onEditingComplete: () {
              onFloorTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!floorTouched) return null;
              return PropertyFormValidators.validateFloor(v)?.message(context);
            },
          ),
          const SizedBox(height: 16),

          // Ascenseur
          SwitchListTile(
            key: const Key('field_has_elevator'),
            title: Text(l10n.propertiesFormElevatorLabel),
            value: hasElevator,
            contentPadding: EdgeInsets.zero,
            onChanged: enabled ? onHasElevatorChanged : null,
          ),

          // Meublé
          SwitchListTile(
            key: const Key('field_furnished'),
            title: Text(l10n.propertiesFormFurnishedLabel),
            subtitle: Text(l10n.propertiesFormFurnishedHelper),
            value: furnished,
            contentPadding: EdgeInsets.zero,
            onChanged: enabled ? onFurnishedChanged : null,
          ),

          const SizedBox(height: 8),

          // Type de chauffage
          DropdownButtonFormField<HeatingType?>(
            key: const Key('field_heating_type'),
            initialValue: selectedHeatingType,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormHeatingTypeLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<HeatingType?>(
                value: null,
                child: Text(l10n.propertiesFormNotSpecified),
              ),
              ...HeatingType.values.map(
                (h) => DropdownMenuItem<HeatingType?>(
                  value: h,
                  child: Text(h.label(context)),
                ),
              ),
            ],
            onChanged: enabled ? onHeatingTypeChanged : null,
          ),
          const SizedBox(height: 16),

          // Année de construction
          TextFormField(
            key: const Key('field_construction_year'),
            controller: constructionYearController,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormConstructionYearLabel,
              hintText: 'Ex. : 1975',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            maxLength: 4,
            onEditingComplete: () {
              onConstructionYearTouched();
            },
            validator: (v) {
              if (!constructionYearTouched) return null;
              return PropertyFormValidators.validateConstructionYear(
                v,
              )?.message(context);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section Financement & acquisition (ExpansionTile) — FEAT-017
// ---------------------------------------------------------------------------

class _FinancementSection extends StatelessWidget {
  const _FinancementSection({
    required this.purchasePriceController,
    required this.notaryFeesController,
    required this.propertyTaxController,
    required this.insurancePnoController,
    required this.condoFeesController,
    required this.loanPrincipalController,
    required this.loanRateController,
    required this.loanInsuranceRateController,
    required this.loanDurationController,
    required this.loanPaymentOverrideController,
    required this.isNewProperty,
    required this.onIsNewPropertyChanged,
    required this.purchaseDate,
    required this.onPurchaseDateChanged,
    required this.loanStartDate,
    required this.onLoanStartDateChanged,
    required this.enabled,
    required this.purchasePriceTouched,
    required this.notaryFeesTouched,
    required this.propertyTaxTouched,
    required this.insurancePnoTouched,
    required this.condoFeesTouched,
    required this.loanPrincipalTouched,
    required this.loanRateTouched,
    required this.loanInsuranceRateTouched,
    required this.loanDurationTouched,
    required this.loanPaymentOverrideTouched,
    required this.onPurchasePriceTouched,
    required this.onNotaryFeesTouched,
    required this.onPropertyTaxTouched,
    required this.onInsurancePnoTouched,
    required this.onCondoFeesTouched,
    required this.onLoanPrincipalTouched,
    required this.onLoanRateTouched,
    required this.onLoanInsuranceRateTouched,
    required this.onLoanDurationTouched,
    required this.onLoanPaymentOverrideTouched,
  });

  final TextEditingController purchasePriceController;
  final TextEditingController notaryFeesController;
  final TextEditingController propertyTaxController;
  final TextEditingController insurancePnoController;
  final TextEditingController condoFeesController;
  final TextEditingController loanPrincipalController;
  final TextEditingController loanRateController;
  final TextEditingController loanInsuranceRateController;
  final TextEditingController loanDurationController;
  final TextEditingController loanPaymentOverrideController;
  final bool isNewProperty;
  final ValueChanged<bool> onIsNewPropertyChanged;
  final DateTime? purchaseDate;
  final ValueChanged<DateTime?> onPurchaseDateChanged;
  final DateTime? loanStartDate;
  final ValueChanged<DateTime?> onLoanStartDateChanged;
  final bool enabled;
  final bool purchasePriceTouched;
  final bool notaryFeesTouched;
  final bool propertyTaxTouched;
  final bool insurancePnoTouched;
  final bool condoFeesTouched;
  final bool loanPrincipalTouched;
  final bool loanRateTouched;
  final bool loanInsuranceRateTouched;
  final bool loanDurationTouched;
  final bool loanPaymentOverrideTouched;
  final VoidCallback onPurchasePriceTouched;
  final VoidCallback onNotaryFeesTouched;
  final VoidCallback onPropertyTaxTouched;
  final VoidCallback onInsurancePnoTouched;
  final VoidCallback onCondoFeesTouched;
  final VoidCallback onLoanPrincipalTouched;
  final VoidCallback onLoanRateTouched;
  final VoidCallback onLoanInsuranceRateTouched;
  final VoidCallback onLoanDurationTouched;
  final VoidCallback onLoanPaymentOverrideTouched;

  Future<void> _pickDate(
    BuildContext context,
    DateTime? current,
    ValueChanged<DateTime?> onChanged,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('section_financement'),
        title: Text(l10n.propertiesFormSectionFinancing),
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        children: [
          // Prix d'achat
          TextFormField(
            key: const Key('field_purchase_price'),
            controller: purchasePriceController,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormPurchasePriceLabel,
              hintText: 'Ex. : 200000',
              suffixText: '€',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onEditingComplete: () {
              onPurchasePriceTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!purchasePriceTouched) return null;
              return PropertyFormValidators.validatePurchasePrice(
                v,
              )?.message(context);
            },
          ),
          const SizedBox(height: 16),

          // Date d'achat
          ListTile(
            key: const Key('field_purchase_date'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              purchaseDate != null
                  ? l10n.propertiesFormPurchaseDateValue(
                      "${purchaseDate!.day.toString().padLeft(2, '0')}/${purchaseDate!.month.toString().padLeft(2, '0')}/${purchaseDate!.year}",
                    )
                  : l10n.propertiesFormPurchaseDateEmpty,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (purchaseDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: l10n.propertiesFormClearDate,
                    onPressed: enabled
                        ? () => onPurchaseDateChanged(null)
                        : null,
                  ),
                IconButton(
                  icon: const Icon(Icons.calendar_today_outlined),
                  tooltip: l10n.propertiesFormPickDate,
                  onPressed: enabled
                      ? () => _pickDate(
                          context,
                          purchaseDate,
                          onPurchaseDateChanged,
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Frais de notaire
          TextFormField(
            key: const Key('field_notary_fees'),
            controller: notaryFeesController,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormNotaryFeesLabel,
              hintText: 'Ex. : 15000',
              suffixText: '€',
              helperText: l10n.propertiesFormNotaryFeesHelper,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onEditingComplete: () {
              onNotaryFeesTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!notaryFeesTouched) return null;
              return PropertyFormValidators.validateNotaryFees(
                v,
              )?.message(context);
            },
          ),
          const SizedBox(height: 8),

          // Bien neuf
          SwitchListTile(
            key: const Key('field_is_new_property'),
            title: Text(l10n.propertiesFormIsNewLabel),
            subtitle: Text(l10n.propertiesFormIsNewHelper),
            value: isNewProperty,
            contentPadding: EdgeInsets.zero,
            onChanged: enabled ? onIsNewPropertyChanged : null,
          ),
          const SizedBox(height: 16),

          // Taxe foncière annuelle
          TextFormField(
            key: const Key('field_property_tax'),
            controller: propertyTaxController,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormPropertyTaxLabel,
              hintText: 'Ex. : 1200',
              suffixText: '€ / an',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onEditingComplete: () {
              onPropertyTaxTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!propertyTaxTouched) return null;
              return PropertyFormValidators.validateAnnualAmount(
                v,
              )?.message(context);
            },
          ),
          const SizedBox(height: 16),

          // Assurance PNO annuelle
          TextFormField(
            key: const Key('field_insurance_pno'),
            controller: insurancePnoController,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormInsurancePnoLabel,
              hintText: 'Ex. : 300',
              suffixText: '€ / an',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onEditingComplete: () {
              onInsurancePnoTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!insurancePnoTouched) return null;
              return PropertyFormValidators.validateAnnualAmount(
                v,
              )?.message(context);
            },
          ),
          const SizedBox(height: 16),

          // Charges copropriété non récupérables
          TextFormField(
            key: const Key('field_condo_fees'),
            controller: condoFeesController,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormCondoFeesLabel,
              hintText: 'Ex. : 600',
              suffixText: '€ / an',
              helperText: l10n.propertiesFormCondoFeesHelper,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onEditingComplete: () {
              onCondoFeesTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!condoFeesTouched) return null;
              return PropertyFormValidators.validateAnnualAmount(
                v,
              )?.message(context);
            },
          ),
          const SizedBox(height: 24),

          // Sous-section prêt immobilier
          _LoanSubSection(
            loanPrincipalController: loanPrincipalController,
            loanRateController: loanRateController,
            loanInsuranceRateController: loanInsuranceRateController,
            loanDurationController: loanDurationController,
            loanPaymentOverrideController: loanPaymentOverrideController,
            loanStartDate: loanStartDate,
            onLoanStartDateChanged: onLoanStartDateChanged,
            enabled: enabled,
            loanPrincipalTouched: loanPrincipalTouched,
            loanRateTouched: loanRateTouched,
            loanInsuranceRateTouched: loanInsuranceRateTouched,
            loanDurationTouched: loanDurationTouched,
            loanPaymentOverrideTouched: loanPaymentOverrideTouched,
            onLoanPrincipalTouched: onLoanPrincipalTouched,
            onLoanRateTouched: onLoanRateTouched,
            onLoanInsuranceRateTouched: onLoanInsuranceRateTouched,
            onLoanDurationTouched: onLoanDurationTouched,
            onLoanPaymentOverrideTouched: onLoanPaymentOverrideTouched,
          ),
        ],
      ),
    );
  }
}

class _LoanSubSection extends StatelessWidget {
  const _LoanSubSection({
    required this.loanPrincipalController,
    required this.loanRateController,
    required this.loanInsuranceRateController,
    required this.loanDurationController,
    required this.loanPaymentOverrideController,
    required this.loanStartDate,
    required this.onLoanStartDateChanged,
    required this.enabled,
    required this.loanPrincipalTouched,
    required this.loanRateTouched,
    required this.loanInsuranceRateTouched,
    required this.loanDurationTouched,
    required this.loanPaymentOverrideTouched,
    required this.onLoanPrincipalTouched,
    required this.onLoanRateTouched,
    required this.onLoanInsuranceRateTouched,
    required this.onLoanDurationTouched,
    required this.onLoanPaymentOverrideTouched,
  });

  final TextEditingController loanPrincipalController;
  final TextEditingController loanRateController;
  final TextEditingController loanInsuranceRateController;
  final TextEditingController loanDurationController;
  final TextEditingController loanPaymentOverrideController;
  final DateTime? loanStartDate;
  final ValueChanged<DateTime?> onLoanStartDateChanged;
  final bool enabled;
  final bool loanPrincipalTouched;
  final bool loanRateTouched;
  final bool loanInsuranceRateTouched;
  final bool loanDurationTouched;
  final bool loanPaymentOverrideTouched;
  final VoidCallback onLoanPrincipalTouched;
  final VoidCallback onLoanRateTouched;
  final VoidCallback onLoanInsuranceRateTouched;
  final VoidCallback onLoanDurationTouched;
  final VoidCallback onLoanPaymentOverrideTouched;

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: loanStartDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) onLoanStartDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.propertiesFormSectionLoan,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        // Capital emprunté
        TextFormField(
          key: const Key('field_loan_principal'),
          controller: loanPrincipalController,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: l10n.propertiesFormLoanPrincipalLabel,
            hintText: 'Ex. : 180000',
            suffixText: '€',
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          onEditingComplete: () {
            onLoanPrincipalTouched();
            FocusScope.of(context).nextFocus();
          },
          validator: (v) {
            if (!loanPrincipalTouched) return null;
            return PropertyFormValidators.validateLoanPrincipal(
              v,
            )?.message(context);
          },
        ),
        const SizedBox(height: 16),
        // Taux nominal + Durée en ligne
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('field_loan_rate'),
                controller: loanRateController,
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: l10n.propertiesFormLoanRateLabel,
                  hintText: '3.5',
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onEditingComplete: () {
                  onLoanRateTouched();
                  FocusScope.of(context).nextFocus();
                },
                validator: (v) {
                  if (!loanRateTouched) return null;
                  return PropertyFormValidators.validateLoanRate(
                    v,
                  )?.message(context);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('field_loan_duration'),
                controller: loanDurationController,
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: l10n.propertiesFormLoanDurationLabel,
                  hintText: '240',
                  suffixText: 'mois',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onEditingComplete: () {
                  onLoanDurationTouched();
                  FocusScope.of(context).nextFocus();
                },
                validator: (v) {
                  if (!loanDurationTouched) return null;
                  return PropertyFormValidators.validateLoanDuration(
                    v,
                  )?.message(context);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Taux assurance emprunteur
        TextFormField(
          key: const Key('field_loan_insurance_rate'),
          controller: loanInsuranceRateController,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: l10n.propertiesFormLoanInsuranceRateLabel,
            hintText: '0.30',
            suffixText: '%',
            helperText: l10n.propertiesFormLoanInsuranceRateHelper,
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onEditingComplete: () {
            onLoanInsuranceRateTouched();
            FocusScope.of(context).nextFocus();
          },
          validator: (v) {
            if (!loanInsuranceRateTouched) return null;
            return PropertyFormValidators.validateInsuranceRate(
              v,
            )?.message(context);
          },
        ),
        const SizedBox(height: 16),
        // Date de début du prêt
        ListTile(
          key: const Key('field_loan_start_date'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            loanStartDate != null
                ? l10n.propertiesFormLoanStartDateValue(
                    "${loanStartDate!.day.toString().padLeft(2, '0')}/${loanStartDate!.month.toString().padLeft(2, '0')}/${loanStartDate!.year}",
                  )
                : l10n.propertiesFormLoanStartDateEmpty,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loanStartDate != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: l10n.propertiesFormClearDate,
                  onPressed: enabled
                      ? () => onLoanStartDateChanged(null)
                      : null,
                ),
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                tooltip: l10n.propertiesFormPickDate,
                onPressed: enabled ? () => _pickDate(context) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Mensualité override
        TextFormField(
          key: const Key('field_loan_payment_override'),
          controller: loanPaymentOverrideController,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: l10n.propertiesFormLoanPaymentOverrideLabel,
            hintText: 'Ex. : 850',
            suffixText: '€ / mois',
            helperText: l10n.propertiesFormLoanPaymentOverrideHelper,
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          onEditingComplete: () {
            onLoanPaymentOverrideTouched();
          },
          validator: (v) {
            if (!loanPaymentOverrideTouched) return null;
            return PropertyFormValidators.validatePurchasePrice(
              v,
            )?.message(context);
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section DPE / GES (ExpansionTile)
// ---------------------------------------------------------------------------

class _DpeSection extends StatelessWidget {
  const _DpeSection({
    required this.dpeValueController,
    required this.selectedDpeLetter,
    required this.onDpeLetterChanged,
    required this.selectedGesLetter,
    required this.onGesLetterChanged,
    required this.enabled,
    required this.dpeValueTouched,
    required this.onDpeValueTouched,
    required this.dpeGesLetters,
  });

  final TextEditingController dpeValueController;
  final String? selectedDpeLetter;
  final ValueChanged<String?> onDpeLetterChanged;
  final String? selectedGesLetter;
  final ValueChanged<String?> onGesLetterChanged;
  final bool enabled;
  final bool dpeValueTouched;
  final VoidCallback onDpeValueTouched;
  final List<String> dpeGesLetters;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('section_dpe'),
        title: Text(l10n.propertiesFormSectionDpe),
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        children: [
          // Classe DPE + Valeur DPE
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<String?>(
                  key: const Key('field_dpe_letter'),
                  initialValue: selectedDpeLetter,
                  decoration: InputDecoration(
                    labelText: l10n.propertiesFormDpeClassLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('—'),
                    ),
                    ...dpeGesLetters.map(
                      (l) =>
                          DropdownMenuItem<String?>(value: l, child: Text(l)),
                    ),
                  ],
                  onChanged: enabled ? onDpeLetterChanged : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('field_dpe_value'),
                  controller: dpeValueController,
                  enabled: enabled,
                  decoration: InputDecoration(
                    labelText: l10n.propertiesFormDpeValueLabel,
                    hintText: 'Ex. : 180',
                    helperText: 'kWh/m²/an',
                    suffixText: 'kWh',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onEditingComplete: () {
                    onDpeValueTouched();
                    FocusScope.of(context).nextFocus();
                  },
                  validator: (v) {
                    if (!dpeValueTouched) return null;
                    return PropertyFormValidators.validateDpeValue(
                      v,
                    )?.message(context);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Classe GES
          DropdownButtonFormField<String?>(
            key: const Key('field_ges_letter'),
            initialValue: selectedGesLetter,
            decoration: InputDecoration(
              labelText: l10n.propertiesFormGesClassLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l10n.propertiesFormGesNotSpecified),
              ),
              ...dpeGesLetters.map(
                (l) => DropdownMenuItem<String?>(value: l, child: Text(l)),
              ),
            ],
            onChanged: enabled ? onGesLetterChanged : null,
          ),
        ],
      ),
    );
  }
}
