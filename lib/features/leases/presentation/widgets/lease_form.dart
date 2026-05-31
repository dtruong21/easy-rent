import 'package:flutter/material.dart';

import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/lease_form_validators.dart';
import '../../../../features/properties/domain/property.dart';
import '../../../../features/tenants/domain/tenant.dart';

/// Champs partagés du formulaire bail.
///
/// Utilisé dans [LeaseFormPage] pour la création et l'édition.
/// La validation est déclenchée inline à la perte de focus.
/// Utiliser un [GlobalKey<LeaseFormWidgetState>] pour appeler [validateAll].
///
/// Séparé de [LeaseFormPage] pour la testabilité unitaire avec des listes
/// mockées de biens et locataires.
class LeaseForm extends StatefulWidget {
  const LeaseForm({
    super.key,
    required this.formKey,
    required this.properties,
    required this.tenants,
    required this.rentController,
    required this.chargesController,
    this.initialPropertyId,
    this.initialTenantId,
    this.initialStartDate,
    this.initialEndDate,
    this.enabled = true,
    required this.onPropertyChanged,
    required this.onTenantChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
  });

  final GlobalKey<FormState> formKey;
  final List<Property> properties;
  final List<Tenant> tenants;
  final TextEditingController rentController;
  final TextEditingController chargesController;

  /// ID du bien pré-sélectionné (mode édition).
  final String? initialPropertyId;

  /// ID du locataire pré-sélectionné (mode édition).
  final String? initialTenantId;

  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final bool enabled;

  final void Function(Property?) onPropertyChanged;
  final void Function(Tenant?) onTenantChanged;
  final void Function(DateTime?) onStartDateChanged;
  final void Function(DateTime?) onEndDateChanged;

  @override
  State<LeaseForm> createState() => LeaseFormWidgetState();
}

/// State public de [LeaseForm] — exposé pour accès via [GlobalKey].
class LeaseFormWidgetState extends State<LeaseForm> {
  Property? _selectedProperty;
  Tenant? _selectedTenant;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isOpenEnded = false; // true = CDI (pas de end_date)

  bool _propertyTouched = false;
  bool _tenantTouched = false;
  bool _rentTouched = false;
  bool _chargesTouched = false;
  bool _startDateTouched = false;

  @override
  void initState() {
    super.initState();
    // Pré-sélection en mode édition
    if (widget.initialPropertyId != null) {
      _selectedProperty = widget.properties
          .where((p) => p.id == widget.initialPropertyId)
          .firstOrNull;
    }
    if (widget.initialTenantId != null) {
      _selectedTenant = widget.tenants
          .where((t) => t.id == widget.initialTenantId)
          .firstOrNull;
    }
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate;
    _isOpenEnded = widget.initialEndDate == null;
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Date de début du bail',
    );
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked;
        _startDateTouched = true;
      });
      widget.onStartDateChanged(picked);
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Date de fin du bail',
    );
    if (picked != null && mounted) {
      setState(() => _endDate = picked);
      widget.onEndDateChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Bien immobilier ---
          if (widget.properties.isEmpty)
            _NoItemsHint(
              message: 'Vous devez d\'abord créer un bien immobilier.',
              route: '/properties/new',
              buttonLabel: 'Créer un bien',
            )
          else
            FormField<Property>(
              key: const Key('field_property'),
              initialValue: _selectedProperty,
              validator: (_) {
                if (!_propertyTouched) return null;
                return LeaseFormValidators.validateProperty(_selectedProperty);
              },
              builder: (state) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<Property>(
                    initialValue: _selectedProperty,
                    decoration: InputDecoration(
                      labelText: 'Bien immobilier *',
                      border: const OutlineInputBorder(),
                      errorText: state.errorText,
                    ),
                    items: widget.properties
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: widget.enabled
                        ? (p) {
                            setState(() {
                              _selectedProperty = p;
                              _propertyTouched = true;
                            });
                            widget.onPropertyChanged(p);
                          }
                        : null,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // --- Locataire ---
          if (widget.tenants.isEmpty)
            _NoItemsHint(
              message: 'Vous devez d\'abord créer un locataire.',
              route: '/tenants/new',
              buttonLabel: 'Créer un locataire',
            )
          else
            FormField<Tenant>(
              key: const Key('field_tenant'),
              initialValue: _selectedTenant,
              validator: (_) {
                if (!_tenantTouched) return null;
                return LeaseFormValidators.validateTenant(_selectedTenant);
              },
              builder: (state) => DropdownButtonFormField<Tenant>(
                initialValue: _selectedTenant,
                decoration: InputDecoration(
                  labelText: 'Locataire *',
                  border: const OutlineInputBorder(),
                  errorText: state.errorText,
                ),
                items: widget.tenants
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(
                          '${t.firstName} ${t.lastName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: widget.enabled
                    ? (t) {
                        setState(() {
                          _selectedTenant = t;
                          _tenantTouched = true;
                        });
                        widget.onTenantChanged(t);
                      }
                    : null,
              ),
            ),
          const SizedBox(height: 16),

          // --- Loyer HC ---
          TextFormField(
            key: const Key('field_rent'),
            controller: widget.rentController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Loyer hors charges (€) *',
              hintText: 'Ex. : 850,00',
              suffixText: '€',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_rentTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _rentTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_rentTouched) return null;
              return LeaseFormValidators.validateRentAmount(v);
            },
          ),
          const SizedBox(height: 16),

          // --- Charges ---
          TextFormField(
            key: const Key('field_charges'),
            controller: widget.chargesController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Charges (€) *',
              hintText: 'Ex. : 50,00 (saisir 0 si aucune charge)',
              suffixText: '€',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_chargesTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _chargesTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_chargesTouched) return null;
              return LeaseFormValidators.validateChargesAmount(v);
            },
          ),
          const SizedBox(height: 16),

          // --- Date de début ---
          FormField<DateTime>(
            key: const Key('field_start_date'),
            initialValue: _startDate,
            validator: (_) {
              if (!_startDateTouched) return null;
              return LeaseFormValidators.validateStartDate(_startDate);
            },
            builder: (state) => InkWell(
              onTap: widget.enabled ? _pickStartDate : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date de début *',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  errorText: state.errorText,
                ),
                child: Text(
                  _startDate != null
                      ? FrenchDate.format(_startDate!)
                      : 'Sélectionner une date',
                  style: _startDate == null
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- Toggle CDI (bail à durée indéterminée) ---
          CheckboxListTile(
            key: const Key('checkbox_open_ended'),
            title: const Text('Bail à durée indéterminée (CDI)'),
            value: _isOpenEnded,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: widget.enabled
                ? (v) {
                    setState(() {
                      _isOpenEnded = v ?? false;
                      if (_isOpenEnded) {
                        _endDate = null;
                        widget.onEndDateChanged(null);
                      }
                    });
                  }
                : null,
          ),

          // --- Date de fin (masquée si CDI) ---
          if (!_isOpenEnded) ...[
            FormField<DateTime>(
              key: const Key('field_end_date'),
              initialValue: _endDate,
              validator: (_) {
                return LeaseFormValidators.validateEndDate(
                  _endDate,
                  _startDate,
                );
              },
              builder: (state) => InkWell(
                onTap: widget.enabled ? _pickEndDate : null,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date de fin',
                    border: const OutlineInputBorder(),
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                    errorText: state.errorText,
                  ),
                  child: Text(
                    _endDate != null
                        ? FrenchDate.format(_endDate!)
                        : 'Optionnelle',
                    style: _endDate == null
                        ? theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Marque tous les champs obligatoires comme "touchés" et valide le formulaire.
  ///
  /// Appelé par [LeaseFormPage] lors du tap sur "Soumettre".
  bool validateAll() {
    setState(() {
      _propertyTouched = true;
      _tenantTouched = true;
      _rentTouched = true;
      _chargesTouched = true;
      _startDateTouched = true;
    });
    return widget.formKey.currentState?.validate() ?? false;
  }

  /// Retourne la date de début courante.
  DateTime? get currentStartDate => _startDate;

  /// Retourne la date de fin courante (null si CDI).
  DateTime? get currentEndDate => _isOpenEnded ? null : _endDate;

  /// Retourne le bien sélectionné.
  Property? get selectedProperty => _selectedProperty;

  /// Retourne le locataire sélectionné.
  Tenant? get selectedTenant => _selectedTenant;
}

/// Hint affiché quand la liste de biens ou locataires est vide.
class _NoItemsHint extends StatelessWidget {
  const _NoItemsHint({
    required this.message,
    required this.route,
    required this.buttonLabel,
  });

  final String message;
  final String route;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withAlpha(60),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withAlpha(80),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
