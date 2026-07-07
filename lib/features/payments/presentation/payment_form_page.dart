import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/payment_form_validators.dart';
import '../../leases/application/lease_detail_provider.dart';
import '../../leases/domain/lease.dart';
import '../application/payment_detail_provider.dart';
import '../application/payment_form_controller.dart';
import '../domain/payment.dart';
import '../domain/payment_form_state.dart';
import '../domain/payment_submit_error.dart';
import 'payment_submit_error_l10n.dart';
import 'widgets/payment_form.dart';

final _log = Logger('PaymentFormPage');

/// Formulaire partagé création / édition d'un paiement.
///
/// - [initial] == null → mode création (titre "Nouveau paiement").
/// - [initial] != null → mode édition (titre "Modifier le paiement", champs pré-remplis).
///
/// Sur succès : SnackBar toast + navigation retour vers la fiche bail.
class PaymentFormPage extends ConsumerStatefulWidget {
  const PaymentFormPage({
    super.key,
    required this.leaseId,
    this.initial,
    this.lease,
  });

  /// ID du bail parent (requis pour le contexte et la navigation retour).
  final String leaseId;

  /// Paiement à éditer, ou [null] pour une création.
  final Payment? initial;

  /// Bail parent (optionnel — chargé si absent pour le pré-remplissage).
  final Lease? lease;

  @override
  ConsumerState<PaymentFormPage> createState() => _PaymentFormPageState();
}

class _PaymentFormPageState extends ConsumerState<PaymentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _formWidgetKey = GlobalKey<PaymentFormWidgetState>();
  late final TextEditingController _rentCtrl;
  late final TextEditingController _chargesCtrl;

  /// Vrai dès que loyer/charges ont été initialisés (paiement en édition, ou
  /// bail). Empêche le pré-remplissage différé (bail chargé en asynchrone via
  /// la route de création) d'écraser une saisie déjà faite par l'utilisateur.
  bool _amountsSeeded = false;

  @override
  void initState() {
    super.initState();
    final payment = widget.initial;
    final lease = widget.lease;

    // Mode édition : pré-remplir depuis le paiement existant.
    // Mode création : pré-remplir depuis le bail si passé au constructeur ;
    // sinon (route /leases/:id/payments/new) il arrive en asynchrone et le
    // pré-remplissage se fait dans build() (voir _seedAmountsFromLease).
    if (payment != null) {
      _rentCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(payment.rentAmountCents),
      );
      _chargesCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(payment.chargesAmountCents),
      );
      _amountsSeeded = true;
    } else if (lease != null) {
      _rentCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(lease.rentAmountCents),
      );
      _chargesCtrl = TextEditingController(
        text: MoneyFormat.centsToInput(lease.chargesAmountCents),
      );
      _amountsSeeded = true;
    } else {
      _rentCtrl = TextEditingController();
      _chargesCtrl = TextEditingController();
    }
  }

  /// Pré-remplit loyer + charges depuis le bail à sa première résolution, en
  /// mode création uniquement, une seule fois (respecte une saisie en cours).
  void _seedAmountsFromLease(Lease lease) {
    if (_amountsSeeded) return;
    _amountsSeeded = true;
    _rentCtrl.text = MoneyFormat.centsToInput(lease.rentAmountCents);
    _chargesCtrl.text = MoneyFormat.centsToInput(lease.chargesAmountCents);
  }

  @override
  void dispose() {
    _rentCtrl.dispose();
    _chargesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(Lease lease) async {
    final formState = _formWidgetKey.currentState;
    if (formState == null || !formState.validateAll()) return;

    final periodStart = formState.currentPeriodStart;
    final periodEnd = formState.currentPeriodEnd;
    final paidAt = formState.currentPaidAt;
    final paymentMethod = formState.currentPaymentMethod;
    final notes = formState.currentNotes;
    final reference = formState.currentReference;

    // Validation finale des dates et du mode de paiement.
    if (PaymentFormValidators.validatePeriodStart(periodStart) != null ||
        PaymentFormValidators.validatePeriodEnd(periodEnd, periodStart) !=
            null ||
        PaymentFormValidators.validatePaidAt(paidAt) != null ||
        PaymentFormValidators.validatePaymentMethod(paymentMethod) != null) {
      return;
    }

    final rentCents = MoneyFormat.eurosToCents(_rentCtrl.text);
    final chargesCents = MoneyFormat.eurosToCents(_chargesCtrl.text);

    if (rentCents == null || chargesCents == null) {
      _log.warning(
        'Montants non parsables après validation — '
        'rent="${_rentCtrl.text}" charges="${_chargesCtrl.text}"',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.paymentsFormInvalidAmountsSnackbar),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
      return;
    }

    // Récupérer l'id du landlord courant pour l'INSERT.
    final landlordId = FirebaseAuth.instance.currentUser?.uid;
    if (landlordId == null) {
      _log.warning('currentUser null lors de submit — session expirée ?');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.paymentsFormSessionExpiredSnackbar),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
      return;
    }

    await ref
        .read(paymentFormControllerProvider.notifier)
        .submit(
          initial: widget.initial,
          leaseId: widget.leaseId,
          landlordId: landlordId,
          periodStart: periodStart!,
          periodEnd: periodEnd!,
          paidAt: paidAt!,
          rentAmountCents: rentCents,
          chargesAmountCents: chargesCents,
          paymentMethod: paymentMethod!,
          notes: notes.isEmpty ? null : notes,
          reference: reference.isEmpty ? null : reference,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.initial == null;

    // Écouter les changements d'état pour les toasts et la navigation.
    ref.listen<PaymentFormState>(paymentFormControllerProvider, (_, next) {
      next.whenOrNull(
        success: (payment) {
          final msg = isCreating
              ? context.l10n.paymentsFormCreatedSnackbar
              : context.l10n.paymentsFormUpdatedSnackbar;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
          context.go('/leases/${widget.leaseId}');
        },
        error: (msg) {
          _log.warning('PaymentFormPage error state: $msg');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(PaymentSubmitError.fromCode(msg).message(context)),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
          );
        },
      );
    });

    final formState = ref.watch(paymentFormControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg) => PaymentSubmitError.fromCode(msg).message(context),
      orElse: () => null,
    );

    // Charger le bail pour le pré-remplissage et les totaux.
    final asyncLease = ref.watch(leaseDetailProvider(widget.leaseId));

    if (asyncLease.isLoading) {
      return Scaffold(
        appBar: AppAppBar(
          title: isCreating
              ? context.l10n.paymentsFormNewTitle
              : context.l10n.paymentsFormEditTitle,
          fallbackRoute: '/leases/${widget.leaseId}',
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final lease = asyncLease.valueOrNull ?? widget.lease;
    if (lease == null) {
      return Scaffold(
        appBar: AppAppBar(
          title: isCreating
              ? context.l10n.paymentsFormNewTitle
              : context.l10n.paymentsFormEditTitle,
          fallbackRoute: '/leases/${widget.leaseId}',
        ),
        body: Center(
          child: Text(context.l10n.paymentsFormLeaseNotFoundMessage),
        ),
      );
    }

    // Création via la route /leases/:id/payments/new : le bail n'est pas passé
    // au constructeur, il arrive ici via leaseDetailProvider → on sème les
    // montants du bail (loyer + charges) dès sa résolution.
    if (isCreating) _seedAmountsFromLease(lease);

    return Scaffold(
      appBar: AppAppBar(
        title: isCreating
            ? context.l10n.paymentsFormNewTitle
            : context.l10n.paymentsFormEditTitle,
        fallbackRoute: '/leases/${widget.leaseId}',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PaymentForm(
              key: _formWidgetKey,
              formKey: _formKey,
              rentController: _rentCtrl,
              chargesController: _chargesCtrl,
              leaseTotalCents: lease.totalAmountCents,
              leaseRentCents: lease.rentAmountCents,
              initialPeriodStart: widget.initial?.periodStart,
              initialPeriodEnd: widget.initial?.periodEnd,
              initialPaidAt: widget.initial?.paidAt,
              initialPaymentMethod: widget.initial?.paymentMethod,
              initialNotes: widget.initial?.notes,
              initialReference: widget.initial?.reference,
              enabled: !isSubmitting,
              onPeriodStartChanged: (_) {},
              onPeriodEndChanged: (_) {},
              onPaidAtChanged: (_) {},
              onPaymentMethodChanged: (_) {},
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
              key: const Key('btn_submit_payment_form'),
              onPressed: isSubmitting ? null : () => _submit(lease),
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      isCreating
                          ? context.l10n.paymentsFormCreateSubmitButton
                          : context.l10n.commonSave,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page d'édition qui charge d'abord la fiche, puis affiche [PaymentFormPage].
///
/// Route : `/leases/:id/payments/:pid/edit`
class PaymentEditPage extends ConsumerWidget {
  const PaymentEditPage({
    super.key,
    required this.leaseId,
    required this.paymentId,
  });

  final String leaseId;
  final String paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPayment = ref.watch(paymentDetailProvider(paymentId));
    final asyncLease = ref.watch(leaseDetailProvider(leaseId));

    if (asyncPayment.isLoading || asyncLease.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (asyncPayment.hasError) {
      return Scaffold(
        appBar: AppAppBar(
          title: context.l10n.paymentsFormEditTitle,
          fallbackRoute: '/leases/$leaseId',
        ),
        body: Center(
          child: Text(
            context.l10n.paymentsEditNotFoundMessage,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    return PaymentFormPage(
      leaseId: leaseId,
      initial: asyncPayment.value,
      lease: asyncLease.valueOrNull,
    );
  }
}
