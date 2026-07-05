import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/utils/money_format.dart';
import '../../properties/application/property_detail_provider.dart';
import '../application/expense_detail_provider.dart';
import '../application/expense_form_controller.dart';
import '../application/property_leases_provider.dart';
import '../domain/expense.dart';
import '../domain/expense_form_state.dart';
import 'expense_form.dart';

final _log = Logger('ExpenseFormPage');

/// Formulaire partagé création / édition d'une dépense.
///
/// - [initial] == null → mode création (titre "Nouvelle dépense").
/// - [initial] != null → mode édition (titre "Modifier la dépense", champs
///   pré-remplis).
///
/// Sur succès : SnackBar toast + `pop()` (retour fiche bien, cohérent
/// FEAT-030) — sauf en création directe sans page précédente, où l'on
/// retombe sur la fiche bien via `go()`.
///
/// ⚠️ FEAT-041a : PAS d'upload de justificatif (réservé FEAT-041b) —
/// `createExpense` est appelé sans `documentId`.
class ExpenseFormPage extends ConsumerStatefulWidget {
  const ExpenseFormPage({
    super.key,
    required this.propertyId,
    this.initial,
    this.preselectedLeaseId,
  });

  /// ID du bien parent (requis pour le contexte et la navigation retour).
  final String propertyId;

  /// Dépense à éditer, ou [null] pour une création.
  final Expense? initial;

  /// Bail pré-sélectionné (passé en `extra` depuis la fiche bail, cf. plan
  /// § h) "Point d'entrée secondaire").
  final String? preselectedLeaseId;

  @override
  ConsumerState<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _formWidgetKey = GlobalKey<ExpenseFormWidgetState>();
  late final TextEditingController _amountCtrl;

  @override
  void initState() {
    super.initState();
    final expense = widget.initial;
    _amountCtrl = TextEditingController(
      text: expense != null
          ? MoneyFormat.centsToInput(expense.amountCents)
          : '',
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formState = _formWidgetKey.currentState;
    if (formState == null || !formState.validateAll()) return;

    final nature = formState.currentNature;
    final expenseDate = formState.currentExpenseDate;
    if (nature == null || expenseDate == null) return;

    final amountCents = MoneyFormat.eurosToCents(_amountCtrl.text);
    if (amountCents == null) {
      _log.warning(
        'Montant non parsable après validation — texte="${_amountCtrl.text}"',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Vérifiez le montant saisi.'),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
      return;
    }

    final periodStart = formState.currentPeriodStart;
    final periodEnd = formState.currentPeriodEnd;
    final notes = formState.currentNotes;

    await ref
        .read(expenseFormControllerProvider.notifier)
        .submit(
          initial: widget.initial,
          propertyId: widget.propertyId,
          leaseId: formState.currentLeaseId,
          amountCents: amountCents,
          expenseDate: expenseDate,
          nature: nature,
          category: formState.currentCategory,
          periodStart: periodStart,
          periodEnd: periodEnd,
          periodYear: (periodStart ?? expenseDate).year,
          notes: notes.isEmpty ? null : notes,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.initial == null;
    final title = isCreating ? 'Nouvelle dépense' : 'Modifier la dépense';
    final fallbackRoute = '/properties/${widget.propertyId}';

    ref.listen<ExpenseFormState>(expenseFormControllerProvider, (_, next) {
      next.whenOrNull(
        success: (expense) {
          final msg = isCreating
              ? 'Dépense enregistrée'
              : 'Modifications enregistrées';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(fallbackRoute);
          }
        },
        error: (msg) {
          _log.warning('ExpenseFormPage error state: $msg');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            ),
          );
        },
      );
    });

    final formState = ref.watch(expenseFormControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );

    final asyncProperty = ref.watch(propertyDetailProvider(widget.propertyId));
    final asyncLeases = ref.watch(propertyLeasesProvider(widget.propertyId));

    if (asyncProperty.isLoading || asyncLeases.isLoading) {
      return Scaffold(
        appBar: AppAppBar(title: title, fallbackRoute: fallbackRoute),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (asyncProperty.hasError) {
      return Scaffold(
        appBar: AppAppBar(title: title, fallbackRoute: fallbackRoute),
        body: const Center(child: Text('Bien introuvable.')),
      );
    }

    final property = asyncProperty.value!;
    final leases = asyncLeases.valueOrNull ?? const [];
    final initial = widget.initial;
    final leaseId = initial?.leaseId ?? widget.preselectedLeaseId;

    return Scaffold(
      appBar: AppAppBar(title: title, fallbackRoute: fallbackRoute),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(property.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ExpenseForm(
              key: _formWidgetKey,
              formKey: _formKey,
              amountController: _amountCtrl,
              leases: leases,
              initialLeaseId: leaseId,
              initialExpenseDate: initial?.expenseDate,
              initialNature: initial?.nature,
              initialCategory: initial?.category,
              initialCategoryOverridden: initial?.categoryOverridden ?? false,
              initialPeriodStart: initial?.periodStart,
              initialPeriodEnd: initial?.periodEnd,
              initialNotes: initial?.notes,
              enabled: !isSubmitting,
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
              key: const Key('btn_submit_expense_form'),
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isCreating ? 'Enregistrer la dépense' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page d'édition qui charge d'abord la fiche, puis affiche [ExpenseFormPage].
///
/// Route : `/properties/:id/expenses/:eid/edit`
class ExpenseEditPage extends ConsumerWidget {
  const ExpenseEditPage({
    super.key,
    required this.propertyId,
    required this.expenseId,
  });

  final String propertyId;
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncExpense = ref.watch(expenseDetailProvider(expenseId));

    return asyncExpense.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppAppBar(
          title: 'Modifier la dépense',
          fallbackRoute: '/properties/$propertyId',
        ),
        body: Center(
          child: Text(
            'Dépense introuvable.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
      data: (expense) =>
          ExpenseFormPage(propertyId: propertyId, initial: expense),
    );
  }
}
