import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../../core/utils/money_format.dart';
import '../../properties/application/property_detail_provider.dart';
import '../application/expense_detail_provider.dart';
import '../application/expense_form_controller.dart';
import '../application/expense_receipt_upload_controller.dart';
import '../application/property_leases_provider.dart';
import '../domain/expense.dart';
import '../domain/expense_form_state.dart';
import '../domain/expense_receipt_upload_state.dart';
import '../domain/expense_submit_error.dart';
import 'expense_form.dart';
import 'expense_submit_error_l10n.dart';

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
/// Justificatif (FEAT-041b) : si un fichier a été uploadé via
/// [ExpenseReceiptField] avant la soumission, son `documentId` est transmis
/// à `createExpense`/`updateExpense`. **Recommandé, non bloquant** — la
/// dépense peut être créée sans justificatif (décision produit #8).
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
          content: Text(context.l10n.expensesFormInvalidAmountSnackbar),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
      return;
    }

    // Justificatif recommandé, non bloquant (décision produit #8) : on
    // n'attend qu'un upload déjà terminé — un upload EN COURS bloque la
    // soumission (évite de créer la dépense sans le documentId attendu par
    // l'utilisateur qui vient de joindre un fichier).
    final receiptState = ref.read(expenseReceiptUploadControllerProvider);
    if (receiptState is ReceiptUploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.expensesFormReceiptUploadInProgressSnackbar,
          ),
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        ),
      );
      return;
    }
    // Correctif review FEAT-041 (finding 6) : un retrait explicite du
    // justificatif déjà attaché (`ReceiptRemoved`, cf.
    // `ExpenseReceiptField`) doit envoyer `documentId: null` — sans ce cas,
    // `widget.initial?.documentId` restait transmis même après un clic sur
    // "Retirer le justificatif" en édition.
    final documentId = switch (receiptState) {
      ReceiptSuccess(:final documentId) => documentId,
      ReceiptRemoved() => null,
      _ => widget.initial?.documentId,
    };

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
          documentId: documentId,
          notes: notes.isEmpty ? null : notes,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.initial == null;
    final title = isCreating
        ? context.l10n.expensesFormNewTitle
        : context.l10n.expensesFormEditTitle;
    final fallbackRoute = '/properties/${widget.propertyId}';

    ref.listen<ExpenseFormState>(expenseFormControllerProvider, (_, next) {
      next.whenOrNull(
        success: (expense) {
          final msg = isCreating
              ? context.l10n.expensesFormCreatedSnackbar
              : context.l10n.expensesFormUpdatedSnackbar;
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
          final reason = ExpenseSubmitError.fromCode(msg);
          _log.warning('ExpenseFormPage error state: ${reason.name}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(reason.message(context)),
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
      error: (msg) => ExpenseSubmitError.fromCode(msg).message(context),
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
        body: Center(
          child: Text(context.l10n.expensesFormPropertyNotFoundMessage),
        ),
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
              propertyId: widget.propertyId,
              initialLeaseId: leaseId,
              initialExpenseDate: initial?.expenseDate,
              initialNature: initial?.nature,
              initialCategory: initial?.category,
              initialCategoryOverridden: initial?.categoryOverridden ?? false,
              initialPeriodStart: initial?.periodStart,
              initialPeriodEnd: initial?.periodEnd,
              initialNotes: initial?.notes,
              initialDocumentId: initial?.documentId,
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
                  : Text(
                      isCreating
                          ? context.l10n.expensesFormCreateSubmitButton
                          : context.l10n.commonSave,
                    ),
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
          title: context.l10n.expensesFormEditTitle,
          fallbackRoute: '/properties/$propertyId',
        ),
        body: Center(
          child: Text(
            context.l10n.expensesEditNotFoundMessage,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
      data: (expense) =>
          ExpenseFormPage(propertyId: propertyId, initial: expense),
    );
  }
}
