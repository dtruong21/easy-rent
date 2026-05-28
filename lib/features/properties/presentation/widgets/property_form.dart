import 'package:flutter/material.dart';

import '../../../../core/utils/property_form_validators.dart';
import '../../../../core/utils/surface_validator.dart';
import '../../domain/property_type.dart';

/// Champs partagés du formulaire bien immobilier.
///
/// Utilisé dans [PropertyFormPage] pour la création et l'édition.
/// La validation est déclenchée inline à la perte de focus.
/// Utiliser un [GlobalKey<PropertyFormWidgetState>] pour appeler [validateAll].
class PropertyForm extends StatefulWidget {
  const PropertyForm({
    super.key,
    required this.formKey,
    required this.nameController,
    required this.addressController,
    required this.surfaceController,
    required this.selectedType,
    required this.onTypeChanged,
    this.enabled = true,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController addressController;
  final TextEditingController surfaceController;
  final PropertyType? selectedType;
  final ValueChanged<PropertyType?> onTypeChanged;
  final bool enabled;

  @override
  State<PropertyForm> createState() => PropertyFormWidgetState();
}

/// State public de [PropertyForm] — exposé pour accès via [GlobalKey].
class PropertyFormWidgetState extends State<PropertyForm> {
  bool _nameTouched = false;
  bool _addressTouched = false;
  bool _surfaceTouched = false;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              hintText: 'Ex. : 12 rue de la Paix, 75001 Paris',
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
    });
    return widget.formKey.currentState?.validate() ?? false;
  }
}
