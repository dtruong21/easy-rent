import 'package:flutter/material.dart';

import '../../../../core/utils/property_form_validators.dart';
import '../../../../core/utils/surface_validator.dart';
import '../../domain/heating_type.dart';
import '../../domain/property_type.dart';

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
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----------------------------------------------------------------
          // Section 1 — Informations principales
          // ----------------------------------------------------------------
          _SectionHeader(title: 'Informations principales'),
          const SizedBox(height: 12),

          // Nom du bien
          TextFormField(
            key: const Key('field_name'),
            controller: widget.nameController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Nom du bien *',
              hintText: 'Ex. : Appartement Paris 11e',
              border: OutlineInputBorder(),
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
              return PropertyFormValidators.validateName(v);
            },
          ),
          const SizedBox(height: 16),

          // Adresse complète
          TextFormField(
            key: const Key('field_address'),
            controller: widget.addressController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Adresse complète *',
              hintText: 'Ex. : 12 rue de la Paix',
              border: OutlineInputBorder(),
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
              return PropertyFormValidators.validateAddress(v);
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
                  decoration: const InputDecoration(
                    labelText: 'Code postal',
                    hintText: '75001',
                    border: OutlineInputBorder(),
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
                    return PropertyFormValidators.validatePostalCode(v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('field_city'),
                  controller: widget.cityController,
                  enabled: widget.enabled,
                  decoration: const InputDecoration(
                    labelText: 'Ville',
                    hintText: 'Paris',
                    border: OutlineInputBorder(),
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
            decoration: const InputDecoration(
              labelText: 'Type de bien *',
              border: OutlineInputBorder(),
            ),
            items: PropertyType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.labelFr)))
                .toList(),
            onChanged: widget.enabled ? widget.onTypeChanged : null,
            validator: (v) =>
                v == null ? 'Veuillez sélectionner un type de bien' : null,
          ),
          const SizedBox(height: 16),

          // Surface (optionnelle)
          TextFormField(
            key: const Key('field_surface'),
            controller: widget.surfaceController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Surface en m² (optionnel)',
              hintText: 'Ex. : 45,5',
              suffixText: 'm²',
              border: OutlineInputBorder(),
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
              return SurfaceValidator.validate(v);
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
          // Section 3 — DPE / GES (optionnel, ExpansionTile)
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
    });
    return widget.formKey.currentState?.validate() ?? false;
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
    return Theme(
      // Supprime le trait de séparation par défaut de l'ExpansionTile.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('section_caracteristiques'),
        title: const Text('Caractéristiques (optionnel)'),
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
                  decoration: const InputDecoration(
                    labelText: 'Pièces',
                    hintText: 'Ex. : 3',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onEditingComplete: () {
                    onRoomsTouched();
                    FocusScope.of(context).nextFocus();
                  },
                  validator: (v) {
                    if (!roomsTouched) return null;
                    return PropertyFormValidators.validateRooms(v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('field_bedrooms'),
                  controller: bedroomsController,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    labelText: 'Chambres',
                    hintText: 'Ex. : 2',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onEditingComplete: () {
                    onBedroomsTouched();
                    FocusScope.of(context).nextFocus();
                  },
                  validator: (v) {
                    if (!bedroomsTouched) return null;
                    return PropertyFormValidators.validateBedrooms(v);
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
            decoration: const InputDecoration(
              labelText: 'Étage',
              hintText: '0',
              helperText: '0 = RDC, négatif autorisé pour sous-sol',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            onEditingComplete: () {
              onFloorTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!floorTouched) return null;
              return PropertyFormValidators.validateFloor(v);
            },
          ),
          const SizedBox(height: 16),

          // Ascenseur
          SwitchListTile(
            key: const Key('field_has_elevator'),
            title: const Text('Ascenseur'),
            value: hasElevator,
            contentPadding: EdgeInsets.zero,
            onChanged: enabled ? onHasElevatorChanged : null,
          ),

          // Meublé
          SwitchListTile(
            key: const Key('field_furnished'),
            title: const Text('Meublé'),
            subtitle: const Text('Impacte la durée légale du bail'),
            value: furnished,
            contentPadding: EdgeInsets.zero,
            onChanged: enabled ? onFurnishedChanged : null,
          ),

          const SizedBox(height: 8),

          // Type de chauffage
          DropdownButtonFormField<HeatingType?>(
            key: const Key('field_heating_type'),
            initialValue: selectedHeatingType,
            decoration: const InputDecoration(
              labelText: 'Type de chauffage',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<HeatingType?>(
                value: null,
                child: Text('Non renseigné'),
              ),
              ...HeatingType.values.map(
                (h) => DropdownMenuItem<HeatingType?>(
                  value: h,
                  child: Text(h.labelFr),
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
            decoration: const InputDecoration(
              labelText: 'Année de construction',
              hintText: 'Ex. : 1975',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            maxLength: 4,
            onEditingComplete: () {
              onConstructionYearTouched();
            },
            validator: (v) {
              if (!constructionYearTouched) return null;
              return PropertyFormValidators.validateConstructionYear(v);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 3 — DPE / GES (ExpansionTile)
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
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('section_dpe'),
        title: const Text('DPE / GES (optionnel)'),
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
                  decoration: const InputDecoration(
                    labelText: 'Classe DPE',
                    border: OutlineInputBorder(),
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
                  decoration: const InputDecoration(
                    labelText: 'Valeur DPE',
                    hintText: 'Ex. : 180',
                    helperText: 'kWh/m²/an',
                    suffixText: 'kWh',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onEditingComplete: () {
                    onDpeValueTouched();
                    FocusScope.of(context).nextFocus();
                  },
                  validator: (v) {
                    if (!dpeValueTouched) return null;
                    return PropertyFormValidators.validateDpeValue(v);
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
            decoration: const InputDecoration(
              labelText: 'Classe GES',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Non renseignée'),
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
