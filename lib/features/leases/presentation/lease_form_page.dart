import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/utils/lease_form_validators.dart';
import '../../../core/utils/money_format.dart';
import '../../../features/properties/application/properties_list_provider.dart';
import '../../../features/tenants/application/tenants_list_provider.dart';
import '../application/lease_detail_provider.dart';
import '../application/lease_form_controller.dart';
import '../application/leases_filter_provider.dart';
import '../data/lease_repository.dart';
import '../../payments/domain/payment_method.dart';
import '../domain/lease.dart';
import '../domain/lease_filter.dart';
import '../domain/lease_form_state.dart';
import '../domain/lease_type.dart';
import 'widgets/active_lease_warning_dialog.dart';
import 'widgets/lease_form.dart';

final _log = Logger('LeaseFormPage');

/// Formulaire partagé création / édition d'un bail.
///
/// - [initial] == null → mode création (titre "Nouveau bail").
/// - [initial] != null → mode édition (titre "Modifier le bail", champs pré-remplis).
///
/// Sur succès : SnackBar toast + navigation vers la liste.
///
/// Avant soumission : vérifie s'il existe un bail actif sur le même bien.
/// Si oui → [ActiveLeaseWarningDialog] avec confirmation explicite.
class LeaseFormPage extends ConsumerStatefulWidget {
  const LeaseFormPage({super.key, this.initial});

  /// Bail à éditer, ou [null] pour une création.
  final Lease? initial;

  @override
  ConsumerState<LeaseFormPage> createState() => _LeaseFormPageState();
}

class _LeaseFormPageState extends ConsumerState<LeaseFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _formWidgetKey = GlobalKey<LeaseFormWidgetState>();

  // Section 2 controllers
  late final TextEditingController _rentCtrl;
  late final TextEditingController _chargesCtrl;
  late final TextEditingController _depositCtrl;
  late final TextEditingController _agencyFeesCtrl;

  // Section 4 controller
  late final TextEditingController _paymentDayCtrl;

  // Section 5 controllers
  late final TextEditingController _irlValueCtrl;
  late final TextEditingController _irlQuarterCtrl;

  @override
  void initState() {
    super.initState();
    final lease = widget.initial;
    _rentCtrl = TextEditingController(
      text: lease != null
          ? MoneyFormat.centsToInput(lease.rentAmountCents)
          : '',
    );
    _chargesCtrl = TextEditingController(
      text: lease != null
          ? MoneyFormat.centsToInput(lease.chargesAmountCents)
          : '',
    );
    _depositCtrl = TextEditingController(
      text: lease?.depositAmountCents != null
          ? MoneyFormat.centsToInput(lease!.depositAmountCents!)
          : '',
    );
    _agencyFeesCtrl = TextEditingController(
      text: lease != null && lease.agencyFeesCents > 0
          ? MoneyFormat.centsToInput(lease.agencyFeesCents)
          : '',
    );
    _paymentDayCtrl = TextEditingController(
      text: lease != null ? lease.paymentDay.toString() : '1',
    );
    _irlValueCtrl = TextEditingController(
      text: lease?.irlIndexValue != null
          ? lease!.irlIndexValue!.toString()
          : '',
    );
    _irlQuarterCtrl = TextEditingController(text: lease?.irlQuarterRef ?? '');
  }

  @override
  void dispose() {
    _rentCtrl.dispose();
    _chargesCtrl.dispose();
    _depositCtrl.dispose();
    _agencyFeesCtrl.dispose();
    _paymentDayCtrl.dispose();
    _irlValueCtrl.dispose();
    _irlQuarterCtrl.dispose();
    super.dispose();
  }

  /// Création d'un locataire SANS quitter le formulaire : push du
  /// formulaire locataire en mode picker (?picker=1 → pop(tenantId) au
  /// succès), attente du refetch de la liste (le controller locataire
  /// invalide tenantsListProvider), puis présélection dans le dropdown.
  Future<void> _onCreateTenantInline() async {
    final newTenantId = await context.push<String>('/tenants/new?picker=1');
    if (newTenantId == null || !mounted) return;
    await ref.read(tenantsListProvider.future);
    if (!mounted) return;
    _formWidgetKey.currentState?.selectTenantById(newTenantId);
  }

  Future<void> _submit() async {
    final formState = _formWidgetKey.currentState;
    if (formState == null || !formState.validateAll()) return;

    final property = formState.selectedProperty;
    final tenant = formState.selectedTenant;
    final startDate = formState.currentStartDate;
    final endDate = formState.currentEndDate;

    if (LeaseFormValidators.validateProperty(property) != null ||
        LeaseFormValidators.validateTenant(tenant) != null ||
        LeaseFormValidators.validateStartDate(startDate) != null) {
      return;
    }

    final rentCents = MoneyFormat.eurosToCents(_rentCtrl.text);
    final chargesCents = MoneyFormat.eurosToCents(_chargesCtrl.text);
    if (rentCents == null || chargesCents == null) return;

    // Optional money fields
    final depositCents = _depositCtrl.text.trim().isEmpty
        ? null
        : MoneyFormat.eurosToCents(_depositCtrl.text);
    final agencyFeesCents = _agencyFeesCtrl.text.trim().isEmpty
        ? 0
        : (MoneyFormat.eurosToCents(_agencyFeesCtrl.text) ?? 0);

    // Section 4 — payment day
    final paymentDayRaw = _paymentDayCtrl.text.trim();
    final paymentDay = paymentDayRaw.isEmpty
        ? 1
        : (int.tryParse(paymentDayRaw) ?? 1);

    // Section 5 — IRL
    final irlRaw = _irlValueCtrl.text.trim();
    final irlValue = irlRaw.isEmpty
        ? null
        : double.tryParse(irlRaw.replaceAll(',', '.'));
    final irlQuarter = _irlQuarterCtrl.text.trim().isEmpty
        ? null
        : _irlQuarterCtrl.text.trim();

    bool hasActiveLease = false;
    try {
      hasActiveLease = await ref
          .read(leaseRepositoryProvider)
          .hasOtherActiveLeaseOnProperty(
            property!.id,
            excludeLeaseId: widget.initial?.id,
          );
    } catch (e, st) {
      _log.warning('hasOtherActiveLeaseOnProperty failed', e, st);
    }

    if (!mounted) return;

    if (hasActiveLease) {
      await showDialog<void>(
        context: context,
        builder: (_) => ActiveLeaseWarningDialog(
          onConfirm: () => _doSubmit(
            propertyId: property!.id,
            tenantId: tenant!.id,
            rentCents: rentCents,
            chargesCents: chargesCents,
            startDate: startDate!,
            endDate: endDate,
            depositAmountCents: depositCents,
            agencyFeesCents: agencyFeesCents,
            paymentDay: paymentDay,
            irlIndexValue: irlValue,
            irlQuarterRef: irlQuarter,
            leaseType: formState.currentLeaseType,
            paymentMethod: formState.currentPaymentMethod,
            solidarityClause: formState.currentSolidarityClause,
            entryInventoryDone: formState.currentEntryInventoryDone,
          ),
        ),
      );
    } else {
      await _doSubmit(
        propertyId: property!.id,
        tenantId: tenant!.id,
        rentCents: rentCents,
        chargesCents: chargesCents,
        startDate: startDate!,
        endDate: endDate,
        depositAmountCents: depositCents,
        agencyFeesCents: agencyFeesCents,
        paymentDay: paymentDay,
        irlIndexValue: irlValue,
        irlQuarterRef: irlQuarter,
        leaseType: formState.currentLeaseType,
        paymentMethod: formState.currentPaymentMethod,
        solidarityClause: formState.currentSolidarityClause,
        entryInventoryDone: formState.currentEntryInventoryDone,
      );
    }
  }

  Future<void> _doSubmit({
    required String propertyId,
    required String tenantId,
    required int rentCents,
    required int chargesCents,
    required DateTime startDate,
    DateTime? endDate,
    int? depositAmountCents,
    int agencyFeesCents = 0,
    int paymentDay = 1,
    double? irlIndexValue,
    String? irlQuarterRef,
    required LeaseType leaseType,
    required PaymentMethod paymentMethod,
    bool solidarityClause = false,
    bool entryInventoryDone = false,
  }) async {
    await ref
        .read(leaseFormControllerProvider.notifier)
        .submit(
          initial: widget.initial,
          propertyId: propertyId,
          tenantId: tenantId,
          rentAmountCents: rentCents,
          chargesAmountCents: chargesCents,
          startDate: startDate,
          endDate: endDate,
          leaseType: leaseType,
          depositAmountCents: depositAmountCents,
          paymentDay: paymentDay,
          paymentMethod: paymentMethod,
          irlIndexValue: irlIndexValue,
          irlQuarterRef: irlQuarterRef,
          agencyFeesCents: agencyFeesCents,
          solidarityClause: solidarityClause,
          entryInventoryDone: entryInventoryDone,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.initial == null;

    ref.listen<LeaseFormState>(leaseFormControllerProvider, (_, next) {
      next.whenOrNull(
        success: (lease) {
          final msg = isCreating ? 'Bail créé' : 'Modifications enregistrées';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
          if (isCreating) {
            // Un filtre hérité d'un drill-down KPI (ex. « À renouveler »)
            // survit à la navigation et masquerait le bail tout juste créé
            // (actif) → retour forcé sur la liste non filtrée. Reset direct
            // du provider : la page /leases sous le formulaire pushé est
            // réutilisée par GoRouter, le seul query param ne suffirait pas.
            // ⚠️ Conservé tel quel (F-2) : NE PAS remplacer par pop(), ce
            // go('/leases?filter=all') est un fix historique qui évite de
            // masquer le bail créé derrière un filtre hérité.
            ref.read(leaseFilterProvider.notifier).state = LeaseFilter.all;
            context.go('/leases?filter=all');
          } else if (context.canPop()) {
            // Édition : la page a été poussée depuis la fiche détail
            // (`/leases/:id/edit`) — pop() y revient plutôt que d'écraser la
            // pile avec la liste (F-2).
            context.pop();
          } else {
            context.go('/leases');
          }
        },
        error: (msg) {
          _log.warning('LeaseFormPage error state');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
          );
        },
      );
    });

    final formState = ref.watch(leaseFormControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );

    final asyncProperties = ref.watch(propertiesListProvider);
    final asyncTenants = ref.watch(tenantsListProvider);

    // hasValue : pendant un refetch (invalidation après création inline
    // d'un locataire), on garde le formulaire monté — le remplacer par un
    // spinner détruirait la saisie en cours.
    if ((asyncProperties.isLoading && !asyncProperties.hasValue) ||
        (asyncTenants.isLoading && !asyncTenants.hasValue)) {
      return Scaffold(
        appBar: AppAppBar(
          title: isCreating ? 'Nouveau bail' : 'Modifier le bail',
          fallbackRoute: '/leases',
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final properties = asyncProperties.valueOrNull ?? [];
    final tenants = asyncTenants.valueOrNull ?? [];

    return Scaffold(
      appBar: AppAppBar(
        title: isCreating ? 'Nouveau bail' : 'Modifier le bail',
        fallbackRoute: '/leases',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LeaseForm(
              key: _formWidgetKey,
              formKey: _formKey,
              properties: properties,
              tenants: tenants,
              rentController: _rentCtrl,
              chargesController: _chargesCtrl,
              depositController: _depositCtrl,
              agencyFeesController: _agencyFeesCtrl,
              paymentDayController: _paymentDayCtrl,
              irlValueController: _irlValueCtrl,
              irlQuarterController: _irlQuarterCtrl,
              initialPropertyId: widget.initial?.propertyId,
              initialTenantId: widget.initial?.tenantId,
              onCreateTenant: isCreating ? _onCreateTenantInline : null,
              initialStartDate: widget.initial?.startDate,
              initialEndDate: widget.initial?.endDate,
              initialLeaseType: widget.initial?.leaseType,
              initialPaymentMethod: widget.initial?.paymentMethod,
              initialSolidarityClause:
                  widget.initial?.solidarityClause ?? false,
              initialEntryInventoryDone:
                  widget.initial?.entryInventoryDone ?? false,
              enabled: !isSubmitting,
              onPropertyChanged: (_) {},
              onTenantChanged: (_) {},
              onStartDateChanged: (_) {},
              onEndDateChanged: (_) {},
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
              key: const Key('btn_submit_lease_form'),
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isCreating ? 'Créer le bail' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page d'édition qui charge d'abord la fiche, puis affiche [LeaseFormPage].
///
/// Route : `/leases/:id/edit`
class LeaseEditPage extends ConsumerWidget {
  const LeaseEditPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLease = ref.watch(leaseDetailProvider(id));

    return asyncLease.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppAppBar(title: 'Modifier le bail', fallbackRoute: '/leases'),
        body: Center(
          child: Text(
            'Bail introuvable.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
      data: (lease) => LeaseFormPage(initial: lease),
    );
  }
}
