import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/utils/surface_validator.dart';
import '../application/property_detail_provider.dart';
import '../application/property_form_controller.dart';
import '../domain/heating_type.dart';
import '../domain/property.dart';
import '../domain/property_form_state.dart';
import '../domain/property_type.dart';
import 'widgets/property_form.dart';

final _log = Logger('PropertyFormPage');

/// Formulaire partagé création / édition d'un bien.
///
/// - [initial] == null → mode création (titre "Nouveau bien").
/// - [initial] != null → mode édition (titre "Modifier le bien", champs pré-remplis).
///
/// Sur succès : SnackBar toast + navigation vers la liste.
class PropertyFormPage extends ConsumerStatefulWidget {
  const PropertyFormPage({super.key, this.initial});

  /// Bien à éditer, ou [null] pour une création.
  final Property? initial;

  @override
  ConsumerState<PropertyFormPage> createState() => _PropertyFormPageState();
}

class _PropertyFormPageState extends ConsumerState<PropertyFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _formWidgetKey = GlobalKey<PropertyFormWidgetState>();

  // Section 1 — Informations principales
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _surfaceCtrl;
  late final TextEditingController _postalCodeCtrl;
  late final TextEditingController _cityCtrl;
  PropertyType? _selectedType;

  // Section 2 — Caractéristiques
  late final TextEditingController _roomsCtrl;
  late final TextEditingController _bedroomsCtrl;
  late final TextEditingController _floorCtrl;
  late final TextEditingController _constructionYearCtrl;
  bool _hasElevator = false;
  bool _furnished = false;
  HeatingType? _selectedHeatingType;

  // Section 3 — DPE / GES
  late final TextEditingController _dpeValueCtrl;
  String? _selectedDpeLetter;
  String? _selectedGesLetter;

  // Section FEAT-017 — Financement & acquisition
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _notaryFeesCtrl;
  late final TextEditingController _propertyTaxCtrl;
  late final TextEditingController _insurancePnoCtrl;
  late final TextEditingController _condoFeesCtrl;
  late final TextEditingController _loanPrincipalCtrl;
  late final TextEditingController _loanRateCtrl;
  late final TextEditingController _loanInsuranceRateCtrl;
  late final TextEditingController _loanDurationCtrl;
  late final TextEditingController _loanPaymentOverrideCtrl;
  bool _isNewProperty = false;
  DateTime? _purchaseDate;
  DateTime? _loanStartDate;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;

    // Section 1
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _addressCtrl = TextEditingController(text: p?.address ?? '');
    _surfaceCtrl = TextEditingController(
      text: p?.surfaceM2 != null
          ? p!.surfaceM2!.toStringAsFixed(p.surfaceM2! % 1 == 0 ? 0 : 2)
          : '',
    );
    _postalCodeCtrl = TextEditingController(text: p?.postalCode ?? '');
    _cityCtrl = TextEditingController(text: p?.city ?? '');
    _selectedType = p?.type ?? PropertyType.appartement;

    // Section 2
    _roomsCtrl = TextEditingController(
      text: p?.rooms != null ? p!.rooms.toString() : '',
    );
    _bedroomsCtrl = TextEditingController(
      text: p?.bedrooms != null ? p!.bedrooms.toString() : '',
    );
    _floorCtrl = TextEditingController(
      text: p?.floor != null ? p!.floor.toString() : '',
    );
    _constructionYearCtrl = TextEditingController(
      text: p?.constructionYear != null ? p!.constructionYear.toString() : '',
    );
    _hasElevator = p?.hasElevator ?? false;
    _furnished = p?.furnished ?? false;
    _selectedHeatingType = p?.heatingType;

    // Section 3
    _dpeValueCtrl = TextEditingController(
      text: p?.dpeValueKwhM2Year != null ? p!.dpeValueKwhM2Year.toString() : '',
    );
    _selectedDpeLetter = p?.dpeLetter;
    _selectedGesLetter = p?.gesLetter;

    // Section FEAT-017 — Financement & acquisition
    _purchasePriceCtrl = TextEditingController(
      text: p?.purchasePriceCents != null
          ? (p!.purchasePriceCents! / 100).toStringAsFixed(0)
          : '',
    );
    _notaryFeesCtrl = TextEditingController(
      text: p?.notaryFeesCents != null
          ? (p!.notaryFeesCents! / 100).toStringAsFixed(0)
          : '',
    );
    _propertyTaxCtrl = TextEditingController(
      text: p?.propertyTaxAnnualCents != null
          ? (p!.propertyTaxAnnualCents! / 100).toStringAsFixed(0)
          : '',
    );
    _insurancePnoCtrl = TextEditingController(
      text: p?.insurancePnoAnnualCents != null
          ? (p!.insurancePnoAnnualCents! / 100).toStringAsFixed(0)
          : '',
    );
    _condoFeesCtrl = TextEditingController(
      text: p?.condoFeesNonRecoverableCents != null
          ? (p!.condoFeesNonRecoverableCents! / 100).toStringAsFixed(0)
          : '',
    );
    _loanPrincipalCtrl = TextEditingController(
      text: p?.loanPrincipalCents != null
          ? (p!.loanPrincipalCents! / 100).toStringAsFixed(0)
          : '',
    );
    _loanRateCtrl = TextEditingController(
      text: p?.loanRateBps != null
          ? (p!.loanRateBps! / 100).toStringAsFixed(2)
          : '',
    );
    _loanInsuranceRateCtrl = TextEditingController(
      text: p?.loanInsuranceBps != null
          ? (p!.loanInsuranceBps! / 100).toStringAsFixed(2)
          : '',
    );
    _loanDurationCtrl = TextEditingController(
      text: p?.loanDurationMonths != null
          ? p!.loanDurationMonths.toString()
          : '',
    );
    _loanPaymentOverrideCtrl = TextEditingController(
      text: p?.loanMonthlyPaymentOverrideCents != null
          ? (p!.loanMonthlyPaymentOverrideCents! / 100).toStringAsFixed(0)
          : '',
    );
    _isNewProperty = p?.isNewProperty ?? false;
    _purchaseDate = p?.purchaseDate;
    _loanStartDate = p?.loanStartDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _surfaceCtrl.dispose();
    _postalCodeCtrl.dispose();
    _cityCtrl.dispose();
    _roomsCtrl.dispose();
    _bedroomsCtrl.dispose();
    _floorCtrl.dispose();
    _constructionYearCtrl.dispose();
    _dpeValueCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _notaryFeesCtrl.dispose();
    _propertyTaxCtrl.dispose();
    _insurancePnoCtrl.dispose();
    _condoFeesCtrl.dispose();
    _loanPrincipalCtrl.dispose();
    _loanRateCtrl.dispose();
    _loanInsuranceRateCtrl.dispose();
    _loanDurationCtrl.dispose();
    _loanPaymentOverrideCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formState = _formWidgetKey.currentState;
    if (formState == null || !formState.validateAll()) return;

    final surface = SurfaceValidator.parse(_surfaceCtrl.text);
    final rooms = int.tryParse(_roomsCtrl.text.trim());
    final bedrooms = int.tryParse(_bedroomsCtrl.text.trim());
    final floor = int.tryParse(_floorCtrl.text.trim());
    final constructionYear = int.tryParse(_constructionYearCtrl.text.trim());
    final dpeValue = int.tryParse(_dpeValueCtrl.text.trim());
    final postalCode = _postalCodeCtrl.text.trim().isEmpty
        ? null
        : _postalCodeCtrl.text.trim();
    final city = _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim();

    // FEAT-017 — extraction champs financement depuis formState widget.
    final financial = formState.extractFinancialData();

    await ref
        .read(propertyFormControllerProvider.notifier)
        .submit(
          initial: widget.initial,
          name: _nameCtrl.text,
          address: _addressCtrl.text,
          type: _selectedType!,
          surfaceM2: surface,
          postalCode: postalCode,
          city: city,
          rooms: rooms,
          bedrooms: bedrooms,
          floor: floor,
          hasElevator: _hasElevator,
          furnished: _furnished,
          heatingType: _selectedHeatingType,
          dpeLetter: _selectedDpeLetter,
          dpeValueKwhM2Year: dpeValue,
          gesLetter: _selectedGesLetter,
          constructionYear: constructionYear,
          purchasePriceCents: financial['purchasePriceCents'] as int?,
          purchaseDate: financial['purchaseDate'] as DateTime?,
          notaryFeesCents: financial['notaryFeesCents'] as int?,
          isNewProperty: financial['isNewProperty'] as bool? ?? false,
          propertyTaxAnnualCents: financial['propertyTaxAnnualCents'] as int?,
          insurancePnoAnnualCents: financial['insurancePnoAnnualCents'] as int?,
          condoFeesNonRecoverableCents:
              financial['condoFeesNonRecoverableCents'] as int?,
          loanPrincipalCents: financial['loanPrincipalCents'] as int?,
          loanRateBps: financial['loanRateBps'] as int?,
          loanInsuranceBps: financial['loanInsuranceBps'] as int?,
          loanDurationMonths: financial['loanDurationMonths'] as int?,
          loanStartDate: financial['loanStartDate'] as DateTime?,
          loanMonthlyPaymentOverrideCents:
              financial['loanMonthlyPaymentOverrideCents'] as int?,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.initial == null;
    final l10n = context.l10n;

    ref.listen<PropertyFormState>(propertyFormControllerProvider, (_, next) {
      next.whenOrNull(
        success: (property) {
          final msg = isCreating
              ? l10n.propertiesCreateSuccessSnackbar
              : l10n.propertiesUpdateSuccessSnackbar;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
          // Édition : la page a été poussée depuis la fiche détail
          // (`/properties/:id/edit`) — pop() y revient. Création : la page a
          // été poussée depuis la liste (`/properties/new`) — go() vers la
          // racine conserve le comportement historique (F-2).
          if (isCreating) {
            context.go('/properties');
          } else if (context.canPop()) {
            context.pop();
          } else {
            context.go('/properties');
          }
        },
        error: (_) {
          _log.warning('PropertyFormPage error state');
        },
      );
    });

    final formState = ref.watch(propertyFormControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppAppBar(
        title: isCreating
            ? l10n.propertiesFormTitleCreate
            : l10n.propertiesFormTitleEdit,
        fallbackRoute: '/properties',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PropertyForm(
              key: _formWidgetKey,
              formKey: _formKey,
              nameController: _nameCtrl,
              addressController: _addressCtrl,
              surfaceController: _surfaceCtrl,
              postalCodeController: _postalCodeCtrl,
              cityController: _cityCtrl,
              roomsController: _roomsCtrl,
              bedroomsController: _bedroomsCtrl,
              floorController: _floorCtrl,
              constructionYearController: _constructionYearCtrl,
              dpeValueController: _dpeValueCtrl,
              selectedType: _selectedType,
              onTypeChanged: (t) => setState(() => _selectedType = t),
              hasElevator: _hasElevator,
              onHasElevatorChanged: (v) => setState(() => _hasElevator = v),
              furnished: _furnished,
              onFurnishedChanged: (v) => setState(() => _furnished = v),
              selectedHeatingType: _selectedHeatingType,
              onHeatingTypeChanged: (h) =>
                  setState(() => _selectedHeatingType = h),
              selectedDpeLetter: _selectedDpeLetter,
              onDpeLetterChanged: (l) => setState(() => _selectedDpeLetter = l),
              selectedGesLetter: _selectedGesLetter,
              onGesLetterChanged: (l) => setState(() => _selectedGesLetter = l),
              enabled: !isSubmitting,
              // FEAT-017 — Financement & acquisition
              purchasePriceController: _purchasePriceCtrl,
              notaryFeesController: _notaryFeesCtrl,
              propertyTaxController: _propertyTaxCtrl,
              insurancePnoController: _insurancePnoCtrl,
              condoFeesController: _condoFeesCtrl,
              loanPrincipalController: _loanPrincipalCtrl,
              loanRateController: _loanRateCtrl,
              loanInsuranceRateController: _loanInsuranceRateCtrl,
              loanDurationController: _loanDurationCtrl,
              loanPaymentOverrideController: _loanPaymentOverrideCtrl,
              isNewProperty: _isNewProperty,
              onIsNewPropertyChanged: (v) => setState(() => _isNewProperty = v),
              purchaseDate: _purchaseDate,
              onPurchaseDateChanged: (d) => setState(() => _purchaseDate = d),
              loanStartDate: _loanStartDate,
              onLoanStartDateChanged: (d) => setState(() => _loanStartDate = d),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('btn_submit_form'),
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      isCreating
                          ? l10n.propertiesFormSubmitCreate
                          : l10n.commonSave,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page d'édition qui charge d'abord la fiche, puis affiche [PropertyFormPage].
///
/// Route : `/properties/:id/edit`
class PropertyEditPage extends ConsumerWidget {
  const PropertyEditPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProperty = ref.watch(propertyDetailProvider(id));

    return asyncProperty.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppAppBar(
          title: context.l10n.propertiesFormTitleEdit,
          fallbackRoute: '/properties',
        ),
        body: Center(
          child: Text(
            context.l10n.propertiesNotFoundShort,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
      data: (property) => PropertyFormPage(initial: property),
    );
  }
}
