import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/lease_form_validators.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../features/payments/domain/payment_method.dart';
import '../../../../features/properties/domain/property.dart';
import '../../../../features/tenants/domain/tenant.dart';
import '../../domain/charge_mode.dart';
import '../../domain/lease_type.dart';

/// Formulaire bail — 5 sections.
///
/// 1. Parties et bien (dropdowns property + tenant).
/// 2. Loyer et charges (loyer HC, charges, dépôt de garantie, honoraires).
/// 3. Type de bail et durée (type, helperText dynamique, dates).
/// 4. Modalités paiement (ExpansionTile) : jour + mode.
/// 5. IRL et clauses (ExpansionTile) : IRL, trimestre, solidarité, état des lieux.
///
/// Utilisé dans [LeaseFormPage] pour la création et l'édition.
/// Utiliser un [GlobalKey<LeaseFormWidgetState>] pour appeler [validateAll].
class LeaseForm extends StatefulWidget {
  const LeaseForm({
    super.key,
    required this.formKey,
    required this.properties,
    required this.tenants,
    required this.rentController,
    required this.chargesController,
    required this.nonRecoverableChargesController,
    required this.depositController,
    required this.agencyFeesController,
    required this.paymentDayController,
    required this.irlValueController,
    required this.irlQuarterController,
    this.initialPropertyId,
    this.initialTenantId,
    this.onCreateTenant,
    this.initialStartDate,
    this.initialEndDate,
    this.initialLeaseType,
    this.initialChargeMode,
    this.initialPaymentMethod,
    this.initialSolidarityClause = false,
    this.initialEntryInventoryDone = false,
    this.enabled = true,
    required this.onPropertyChanged,
    required this.onTenantChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
  });

  final GlobalKey<FormState> formKey;
  final List<Property> properties;
  final List<Tenant> tenants;

  // --- Section 2 controllers ---
  final TextEditingController rentController;
  final TextEditingController chargesController;
  final TextEditingController nonRecoverableChargesController;
  final TextEditingController depositController;
  final TextEditingController agencyFeesController;

  // --- Section 4 controller ---
  final TextEditingController paymentDayController;

  // --- Section 5 controllers ---
  final TextEditingController irlValueController;
  final TextEditingController irlQuarterController;

  /// ID du bien pré-sélectionné (mode édition).
  final String? initialPropertyId;

  /// ID du locataire pré-sélectionné (mode édition).
  final String? initialTenantId;

  /// Si non-null, affiche un raccourci « Nouveau locataire » sous le picker
  /// (flux création de bail sans repasser par la liste des locataires).
  final VoidCallback? onCreateTenant;

  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final LeaseType? initialLeaseType;

  /// Mode de charges pré-sélectionné (mode édition). `null` en création ou
  /// pour un bail pré-042 — le formulaire dérive alors le défaut à partir du
  /// type de bail (FEAT-042, cf. `LeaseFormWidgetState._resolveChargeMode`).
  final ChargeMode? initialChargeMode;
  final PaymentMethod? initialPaymentMethod;
  final bool initialSolidarityClause;
  final bool initialEntryInventoryDone;
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
  bool _isOpenEnded = false;
  LeaseType _leaseType = LeaseType.unfurnished;

  /// Mode de charges courant — jamais `null` dans le formulaire (l'ambiguïté
  /// "pré-042" n'a de sens qu'en base ; l'utilisateur choisit toujours
  /// explicitement ou hérite d'un défaut cohérent avec le type, FEAT-042).
  ChargeMode _chargeMode = ChargeMode.provisions;
  PaymentMethod _paymentMethod = PaymentMethod.virement;
  bool _solidarityClause = false;
  bool _entryInventoryDone = false;

  bool _propertyTouched = false;
  bool _tenantTouched = false;

  // Incrémenté par [selectTenantById] : le DropdownButtonFormField fige son
  // initialValue à la création — changer la clé du sous-arbre force sa
  // re-création avec la sélection programmatique (locataire tout juste créé).
  int _tenantFieldGeneration = 0;
  bool _rentTouched = false;
  bool _chargesTouched = false;
  bool _nonRecoverableChargesTouched = false;
  bool _depositTouched = false;
  bool _agencyFeesTouched = false;
  bool _startDateTouched = false;
  bool _paymentDayTouched = false;
  bool _irlValueTouched = false;
  bool _irlQuarterTouched = false;

  @override
  void initState() {
    super.initState();
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
    _leaseType = widget.initialLeaseType ?? LeaseType.unfurnished;
    _chargeMode = _resolveChargeMode(_leaseType, widget.initialChargeMode);
    _paymentMethod = widget.initialPaymentMethod ?? PaymentMethod.virement;
    _solidarityClause = widget.initialSolidarityClause;
    _entryInventoryDone = widget.initialEntryInventoryDone;
  }

  /// Résout le mode de charges à appliquer pour un [type] de bail donné,
  /// en tenant compte d'un [requested] mode (choix utilisateur ou valeur
  /// pré-existante) — FEAT-042. Miroir client de la cohérence imposée côté
  /// serveur (`resolveChargeMode` dans `lease_payment.ts`) :
  /// - nu → provisions (forcé)
  /// - mobilité → forfait (forcé)
  /// - meublé / étudiant → [requested] si fourni, sinon provisions (défaut).
  static ChargeMode _resolveChargeMode(LeaseType type, ChargeMode? requested) {
    return switch (type) {
      LeaseType.unfurnished => ChargeMode.provisions,
      LeaseType.mobility => ChargeMode.forfait,
      LeaseType.furnished ||
      LeaseType.student => requested ?? ChargeMode.provisions,
    };
  }

  /// Vrai si le mode de charges est verrouillé (non modifiable par
  /// l'utilisateur) pour le type de bail courant — nu (provisions forcé) et
  /// mobilité (forfait forcé, loi ELAN art. 25-18).
  bool get _chargeModeLocked =>
      _leaseType == LeaseType.unfurnished || _leaseType == LeaseType.mobility;

  /// Sélectionne le locataire [id] (créé inline depuis le formulaire) —
  /// no-op si l'id est absent de [LeaseForm.tenants] (liste pas encore
  /// rafraîchie : l'appelant doit attendre le refetch avant d'appeler).
  void selectTenantById(String id) {
    final tenant = widget.tenants.where((t) => t.id == id).firstOrNull;
    if (tenant == null) return;
    setState(() {
      _selectedTenant = tenant;
      _tenantTouched = true;
      _tenantFieldGeneration++;
    });
    widget.onTenantChanged(tenant);
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
    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ----------------------------------------------------------------
          // Section 1 — Parties et bien
          // ----------------------------------------------------------------
          _SectionHeader(title: 'Parties et bien'),
          const SizedBox(height: 12),
          _buildPropertyField(),
          const SizedBox(height: 16),
          _buildTenantField(),

          const SizedBox(height: 24),

          // ----------------------------------------------------------------
          // Section 2 — Loyer et charges
          // ----------------------------------------------------------------
          _SectionHeader(title: 'Loyer et charges'),
          const SizedBox(height: 12),
          _buildRentField(),
          const SizedBox(height: 16),
          _buildChargesField(),
          const SizedBox(height: 16),
          _buildNonRecoverableChargesField(),
          const SizedBox(height: 16),
          _buildDepositField(),
          const SizedBox(height: 16),
          _buildAgencyFeesField(),

          const SizedBox(height: 24),

          // ----------------------------------------------------------------
          // Section 3 — Type de bail et durée
          // ----------------------------------------------------------------
          _SectionHeader(title: 'Type de bail et durée'),
          const SizedBox(height: 12),
          _buildLeaseTypeField(),
          const SizedBox(height: 16),
          _buildChargeModeField(),
          const SizedBox(height: 16),
          _buildStartDateField(),
          const SizedBox(height: 16),
          _buildOpenEndedToggle(),
          if (!_isOpenEnded) ...[
            const SizedBox(height: 16),
            _buildEndDateField(),
          ],

          const SizedBox(height: 16),

          // ----------------------------------------------------------------
          // Section 4 — Modalités paiement (ExpansionTile)
          // ----------------------------------------------------------------
          _PaymentSection(
            paymentDayController: widget.paymentDayController,
            paymentMethod: _paymentMethod,
            onPaymentMethodChanged: (m) =>
                setState(() => _paymentMethod = m ?? PaymentMethod.virement),
            enabled: widget.enabled,
            paymentDayTouched: _paymentDayTouched,
            onPaymentDayTouched: () =>
                setState(() => _paymentDayTouched = true),
          ),

          const SizedBox(height: 16),

          // ----------------------------------------------------------------
          // Section 5 — IRL et clauses (ExpansionTile)
          // ----------------------------------------------------------------
          _IrlClausesSection(
            irlValueController: widget.irlValueController,
            irlQuarterController: widget.irlQuarterController,
            solidarityClause: _solidarityClause,
            entryInventoryDone: _entryInventoryDone,
            onSolidarityChanged: (v) =>
                setState(() => _solidarityClause = v ?? false),
            onEntryInventoryChanged: (v) =>
                setState(() => _entryInventoryDone = v ?? false),
            enabled: widget.enabled,
            irlValueTouched: _irlValueTouched,
            onIrlValueTouched: () => setState(() => _irlValueTouched = true),
            irlQuarterTouched: _irlQuarterTouched,
            onIrlQuarterTouched: () =>
                setState(() => _irlQuarterTouched = true),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section 1 widgets
  // ---------------------------------------------------------------------------

  Widget _buildPropertyField() {
    if (widget.properties.isEmpty) {
      return _NoItemsHint(
        message: 'Vous devez d\'abord créer un bien immobilier.',
        route: '/properties/new',
        buttonLabel: 'Créer un bien',
      );
    }
    return FormField<Property>(
      key: const Key('field_property'),
      initialValue: _selectedProperty,
      validator: (_) {
        if (!_propertyTouched) return null;
        return LeaseFormValidators.validateProperty(_selectedProperty);
      },
      builder: (state) => DropdownButtonFormField<Property>(
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
                child: Text(p.name, overflow: TextOverflow.ellipsis),
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
    );
  }

  Widget _buildTenantField() {
    if (widget.tenants.isEmpty) {
      // Aucun locataire : bandeau explicatif + création inline sans quitter
      // le formulaire (le bail en cours de saisie est préservé) — avant, le
      // bandeau n'offrait aucune action et forçait le détour par le
      // dashboard (retour utilisateur 2026-07-02).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NoItemsHint(
            message: 'Vous devez d\'abord créer un locataire.',
            route: '/tenants/new',
            buttonLabel: 'Créer un locataire',
          ),
          if (widget.onCreateTenant != null) _createTenantButton(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: ValueKey('tenant_field_gen_$_tenantFieldGeneration'),
          child: _buildTenantDropdown(),
        ),
        if (widget.onCreateTenant != null) _createTenantButton(),
      ],
    );
  }

  Widget _createTenantButton() => TextButton.icon(
    key: const Key('btn_create_tenant_inline'),
    onPressed: widget.enabled ? widget.onCreateTenant : null,
    icon: const Icon(Icons.person_add_outlined, size: 18),
    label: const Text('Nouveau locataire'),
  );

  Widget _buildTenantDropdown() {
    return FormField<Tenant>(
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
    );
  }

  // ---------------------------------------------------------------------------
  // Section 2 widgets
  // ---------------------------------------------------------------------------

  Widget _buildRentField() => TextFormField(
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
  );

  /// Libellé + texte d'aide du champ charges — dynamique selon le mode de
  /// charges (FEAT-042) : provisions récupérables (régularisables) vs
  /// forfait libératoire (montant unique, non ventilable).
  (String, String) get _chargesFieldLabels => switch (_chargeMode) {
    ChargeMode.provisions => (
      'Charges récupérables (€) *',
      'Provisions mensuelles refacturables au locataire (décret n°87-713)',
    ),
    ChargeMode.forfait => (
      'Forfait de charges (€) *',
      'Forfait mensuel libératoire — non régularisable.',
    ),
  };

  Widget _buildChargesField() {
    final (label, helper) = _chargesFieldLabels;
    return TextFormField(
      key: const Key('field_charges'),
      controller: widget.chargesController,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Ex. : 50,00 (saisir 0 si aucune charge)',
        helperText: helper,
        suffixText: '€',
        border: const OutlineInputBorder(),
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
    );
  }

  /// Champ "Charges non récupérables" — masqué en mode forfait (FEAT-042) :
  /// un forfait est un montant unique libératoire, non ventilable entre
  /// récupérable/non récupérable (le serveur force la valeur à 0 dans ce
  /// mode, cf. `lease_payment.ts`).
  Widget _buildNonRecoverableChargesField() {
    if (_chargeMode == ChargeMode.forfait) return const SizedBox.shrink();
    return TextFormField(
      key: const Key('field_non_recoverable_charges'),
      controller: widget.nonRecoverableChargesController,
      enabled: widget.enabled,
      decoration: const InputDecoration(
        labelText: 'Charges non récupérables (€)',
        hintText: 'Ex. : 20,00 (saisir 0 si aucune)',
        helperText:
            'À la charge du bailleur — non refacturable au locataire. '
            'Saisir 0 si aucune.',
        suffixText: '€',
        border: OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) {
        if (_nonRecoverableChargesTouched) setState(() {});
      },
      onEditingComplete: () {
        setState(() => _nonRecoverableChargesTouched = true);
        FocusScope.of(context).nextFocus();
      },
      validator: (v) {
        if (!_nonRecoverableChargesTouched) return null;
        return LeaseFormValidators.validateNonRecoverableCharges(v);
      },
    );
  }

  Widget _buildDepositField() => TextFormField(
    key: const Key('field_deposit'),
    controller: widget.depositController,
    enabled: widget.enabled,
    decoration: const InputDecoration(
      labelText: 'Dépôt de garantie (€)',
      hintText: 'Ex. : 850,00',
      helperText: 'Optionnel',
      suffixText: '€',
      border: OutlineInputBorder(),
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) {
      if (_depositTouched) setState(() {});
    },
    onEditingComplete: () {
      setState(() => _depositTouched = true);
      FocusScope.of(context).nextFocus();
    },
    validator: (v) {
      if (!_depositTouched) return null;
      if (v == null || v.trim().isEmpty) return null;
      final cents = MoneyFormat.eurosToCents(v);
      return LeaseFormValidators.validateDepositCents(cents);
    },
  );

  Widget _buildAgencyFeesField() => TextFormField(
    key: const Key('field_agency_fees'),
    controller: widget.agencyFeesController,
    enabled: widget.enabled,
    decoration: const InputDecoration(
      labelText: 'Honoraires d\'agence (€)',
      hintText: 'Ex. : 500,00 (0 si aucun)',
      helperText: 'Optionnel — saisir 0 si pas d\'agence',
      suffixText: '€',
      border: OutlineInputBorder(),
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) {
      if (_agencyFeesTouched) setState(() {});
    },
    onEditingComplete: () {
      setState(() => _agencyFeesTouched = true);
      FocusScope.of(context).nextFocus();
    },
    validator: (v) {
      if (!_agencyFeesTouched) return null;
      if (v == null || v.trim().isEmpty) return null;
      final cents = MoneyFormat.eurosToCents(v);
      return LeaseFormValidators.validateAgencyFees(cents);
    },
  );

  // ---------------------------------------------------------------------------
  // Section 3 widgets
  // ---------------------------------------------------------------------------

  Widget _buildLeaseTypeField() => DropdownButtonFormField<LeaseType>(
    key: const Key('field_lease_type'),
    initialValue: _leaseType,
    decoration: InputDecoration(
      labelText: 'Type de bail *',
      helperText: _leaseType.formHelperText,
      border: const OutlineInputBorder(),
    ),
    items: LeaseType.values
        .map((t) => DropdownMenuItem(value: t, child: Text(t.labelFr)))
        .toList(),
    onChanged: widget.enabled
        ? (t) => setState(() {
            _leaseType = t ?? LeaseType.unfurnished;
            // FEAT-042 : recalculer le mode de charges pour respecter la
            // cohérence type↔mode (nu→provisions, mobilité→forfait). Si le
            // type reste libre (meublé/étudiant), on conserve le choix
            // courant plutôt que de le réinitialiser.
            _chargeMode = _resolveChargeMode(_leaseType, _chargeMode);
          })
        : null,
  );

  /// Sélecteur du mode de charges (FEAT-042).
  ///
  /// - Nu : provisions verrouillé + note légale.
  /// - Meublé / étudiant : `SegmentedButton` Provisions | Forfait, libre.
  /// - Mobilité : forfait verrouillé + note légale.
  Widget _buildChargeModeField() {
    final theme = Theme.of(context);
    final locked = _chargeModeLocked;
    final helperText = switch (_leaseType) {
      LeaseType.unfurnished =>
        'Bail vide : provisions + régularisation annuelle obligatoire '
            '(art. 23).',
      LeaseType.mobility =>
        'Bail mobilité : forfait obligatoire, non régularisable '
            '(loi ELAN art. 25-18).',
      LeaseType.furnished || LeaseType.student =>
        'Meublé : provisions (régularisables) ou forfait (libératoire, '
            'art. 25-10).',
    };

    return FormField<ChargeMode>(
      key: const Key('field_charge_mode'),
      initialValue: _chargeMode,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mode de charges', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<ChargeMode>(
            key: const Key('segmented_charge_mode'),
            segments: const [
              ButtonSegment(
                value: ChargeMode.provisions,
                label: Text('Provisions'),
              ),
              ButtonSegment(value: ChargeMode.forfait, label: Text('Forfait')),
            ],
            selected: {_chargeMode},
            onSelectionChanged: (widget.enabled && !locked)
                ? (selection) => setState(() => _chargeMode = selection.first)
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            helperText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartDateField() {
    final theme = Theme.of(context);
    return FormField<DateTime>(
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
    );
  }

  Widget _buildOpenEndedToggle() => CheckboxListTile(
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
  );

  Widget _buildEndDateField() {
    final theme = Theme.of(context);
    return FormField<DateTime>(
      key: const Key('field_end_date'),
      initialValue: _endDate,
      validator: (_) =>
          LeaseFormValidators.validateEndDate(_endDate, _startDate),
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
            _endDate != null ? FrenchDate.format(_endDate!) : 'Optionnelle',
            style: _endDate == null
                ? theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API — exposed via GlobalKey
  // ---------------------------------------------------------------------------

  /// Marque tous les champs obligatoires comme "touchés" et valide le formulaire.
  bool validateAll() {
    setState(() {
      _propertyTouched = true;
      _tenantTouched = true;
      _rentTouched = true;
      _chargesTouched = true;
      _nonRecoverableChargesTouched = true;
      _depositTouched = true;
      _agencyFeesTouched = true;
      _startDateTouched = true;
      _paymentDayTouched = true;
      _irlValueTouched = true;
      _irlQuarterTouched = true;
    });
    return widget.formKey.currentState?.validate() ?? false;
  }

  DateTime? get currentStartDate => _startDate;
  DateTime? get currentEndDate => _isOpenEnded ? null : _endDate;
  Property? get selectedProperty => _selectedProperty;
  Tenant? get selectedTenant => _selectedTenant;
  LeaseType get currentLeaseType => _leaseType;

  /// Mode de charges courant (FEAT-042) — toujours non-null côté formulaire.
  ChargeMode get currentChargeMode => _chargeMode;
  PaymentMethod get currentPaymentMethod => _paymentMethod;
  bool get currentSolidarityClause => _solidarityClause;
  bool get currentEntryInventoryDone => _entryInventoryDone;
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
// Section 4 — Modalités paiement (ExpansionTile)
// ---------------------------------------------------------------------------

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({
    required this.paymentDayController,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    required this.enabled,
    required this.paymentDayTouched,
    required this.onPaymentDayTouched,
  });

  final TextEditingController paymentDayController;
  final PaymentMethod paymentMethod;
  final ValueChanged<PaymentMethod?> onPaymentMethodChanged;
  final bool enabled;
  final bool paymentDayTouched;
  final VoidCallback onPaymentDayTouched;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('section_payment_terms'),
        title: const Text('Modalités paiement (optionnel)'),
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        children: [
          // Jour d'échéance
          TextFormField(
            key: const Key('field_payment_day'),
            controller: paymentDayController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Jour d\'échéance',
              hintText: '1',
              helperText: 'Jour du mois où le loyer est dû (1 à 28)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onEditingComplete: () {
              onPaymentDayTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!paymentDayTouched) return null;
              if (v == null || v.trim().isEmpty) return null;
              return LeaseFormValidators.validatePaymentDay(v);
            },
          ),
          const SizedBox(height: 16),

          // Mode de paiement
          DropdownButtonFormField<PaymentMethod>(
            key: const Key('field_payment_method'),
            initialValue: paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Mode de paiement',
              border: OutlineInputBorder(),
            ),
            items: PaymentMethod.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: enabled ? onPaymentMethodChanged : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 5 — IRL et clauses (ExpansionTile)
// ---------------------------------------------------------------------------

class _IrlClausesSection extends StatelessWidget {
  const _IrlClausesSection({
    required this.irlValueController,
    required this.irlQuarterController,
    required this.solidarityClause,
    required this.entryInventoryDone,
    required this.onSolidarityChanged,
    required this.onEntryInventoryChanged,
    required this.enabled,
    required this.irlValueTouched,
    required this.onIrlValueTouched,
    required this.irlQuarterTouched,
    required this.onIrlQuarterTouched,
  });

  final TextEditingController irlValueController;
  final TextEditingController irlQuarterController;
  final bool solidarityClause;
  final bool entryInventoryDone;
  final ValueChanged<bool?> onSolidarityChanged;
  final ValueChanged<bool?> onEntryInventoryChanged;
  final bool enabled;
  final bool irlValueTouched;
  final VoidCallback onIrlValueTouched;
  final bool irlQuarterTouched;
  final VoidCallback onIrlQuarterTouched;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('section_irl_clauses'),
        title: const Text('IRL et clauses (optionnel)'),
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        children: [
          // Valeur IRL initiale
          TextFormField(
            key: const Key('field_irl_value'),
            controller: irlValueController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Valeur IRL initiale',
              hintText: 'Ex. : 142.43',
              helperText: 'Indice de référence des loyers (optionnel)',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onEditingComplete: () {
              onIrlValueTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!irlValueTouched) return null;
              return LeaseFormValidators.validateIrlValue(v);
            },
          ),
          const SizedBox(height: 16),

          // Trimestre IRL de référence
          TextFormField(
            key: const Key('field_irl_quarter'),
            controller: irlQuarterController,
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Trimestre IRL de référence',
              hintText: 'T1-2026',
              helperText: 'Format : T1-2026, T2-2026, etc.',
              border: OutlineInputBorder(),
            ),
            onEditingComplete: () {
              onIrlQuarterTouched();
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!irlQuarterTouched) return null;
              return LeaseFormValidators.validateIrlQuarter(v);
            },
          ),
          const SizedBox(height: 8),

          // Clause de solidarité
          SwitchListTile(
            key: const Key('switch_solidarity_clause'),
            title: const Text('Clause de solidarité'),
            subtitle: const Text('Solidarité entre colocataires'),
            value: solidarityClause,
            contentPadding: EdgeInsets.zero,
            onChanged: enabled ? onSolidarityChanged : null,
          ),

          // État des lieux d'entrée
          SwitchListTile(
            key: const Key('switch_entry_inventory'),
            title: const Text('État des lieux d\'entrée réalisé'),
            value: entryInventoryDone,
            contentPadding: EdgeInsets.zero,
            onChanged: enabled ? onEntryInventoryChanged : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hint — liste vide
// ---------------------------------------------------------------------------

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
