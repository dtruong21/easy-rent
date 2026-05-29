import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/utils/lease_form_validators.dart';
import '../../../core/utils/money_format.dart';
import '../../../features/properties/application/properties_list_provider.dart';
import '../../../features/tenants/application/tenants_list_provider.dart';
import '../application/lease_detail_provider.dart';
import '../application/lease_form_controller.dart';
import '../data/lease_repository.dart';
import '../domain/lease.dart';
import '../domain/lease_form_state.dart';
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
  late final TextEditingController _rentCtrl;
  late final TextEditingController _chargesCtrl;

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
  }

  @override
  void dispose() {
    _rentCtrl.dispose();
    _chargesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formState = _formWidgetKey.currentState;
    if (formState == null || !formState.validateAll()) return;

    // Lire les valeurs depuis le widget form
    final property = formState.selectedProperty;
    final tenant = formState.selectedTenant;
    final startDate = formState.currentStartDate;
    final endDate = formState.currentEndDate;

    // Validation finale (propriété et locataire peuvent être null si listes vides)
    if (LeaseFormValidators.validateProperty(property) != null ||
        LeaseFormValidators.validateTenant(tenant) != null ||
        LeaseFormValidators.validateStartDate(startDate) != null) {
      return;
    }

    final rentCents = MoneyFormat.eurosToCents(_rentCtrl.text);
    final chargesCents = MoneyFormat.eurosToCents(_chargesCtrl.text);

    if (rentCents == null || chargesCents == null) return;

    // Soft warning — TOCTOU race accepted (no DB constraint), see docs/plans/FEAT-005-crud-leases.md
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
      // En cas d'erreur, on laisse passer (non bloquant).
    }

    if (!mounted) return;

    if (hasActiveLease) {
      // Afficher le dialog d'avertissement — l'utilisateur peut confirmer ou annuler.
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
        );
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.initial == null;

    // Écouter les changements d'état pour les toasts et la navigation.
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
          context.go('/leases');
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

    // Charger les listes de biens et locataires pour les dropdowns.
    final asyncProperties = ref.watch(propertiesListProvider);
    final asyncTenants = ref.watch(tenantsListProvider);

    // Afficher un loader si les listes ne sont pas encore prêtes.
    if (asyncProperties.isLoading || asyncTenants.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(isCreating ? 'Nouveau bail' : 'Modifier le bail'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final properties = asyncProperties.valueOrNull ?? [];
    final tenants = asyncTenants.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(isCreating ? 'Nouveau bail' : 'Modifier le bail'),
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
              initialPropertyId: widget.initial?.propertyId,
              initialTenantId: widget.initial?.tenantId,
              initialStartDate: widget.initial?.startDate,
              initialEndDate: widget.initial?.endDate,
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
        appBar: AppBar(title: const Text('Modifier le bail')),
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
