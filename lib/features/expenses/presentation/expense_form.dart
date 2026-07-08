import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/utils/expense_form_validators.dart';
import '../../../core/utils/french_date.dart';
import '../../../core/validation/validation_error_l10n.dart';
import '../../leases/domain/lease.dart';
import '../../leases/domain/lease_status.dart';
import '../domain/expense_category.dart';
import '../domain/expense_nature.dart';
import 'expense_category_l10n.dart';
import 'expense_nature_l10n.dart';
import 'expense_receipt_field.dart';

/// Libellé localisé d'un [LeaseStatus], pour l'item du dropdown "Bail
/// concerné" (FEAT-043).
///
/// Petit mapping local plutôt qu'une extension `leases/presentation/` :
/// [leaseStatusPill] (`lib/features/leases/presentation/widgets/lease_status_mapper.dart`)
/// calcule aussi les statuts dérivés « en retard »/« à renouveler », ce qui
/// nécessite l'historique des paiements du bail — hors de propos pour un
/// simple libellé de dropdown. Réutilise les clés `leasesStatus*` déjà
/// définies (pas de nouvelle clé `expenses*` pour un libellé qui appartient
/// sémantiquement au domaine `leases`).
String _leaseStatusLabel(BuildContext context, LeaseStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    LeaseStatus.active => l10n.leasesStatusActive,
    LeaseStatus.terminated => l10n.leasesStatusTerminated,
    LeaseStatus.archived => l10n.leasesStatusArchived,
  };
}

/// Champs partagés du formulaire dépense.
///
/// Utilisé dans [ExpenseFormPage] pour la création et l'édition.
///
/// Comportement clé (cf. `docs/plans/FEAT-041-depenses.md` § a)/h)) :
/// - Le bail est **optionnel**, dropdown des baux du bien.
/// - La nature **présélectionne** la catégorie (`nature.defaultCategory`).
/// - **Verrouillage dur** sur les natures verrouillées
///   ([ExpenseNature.isCategoryLocked]) : impossible de forcer la catégorie.
/// - **Avertissement explicite** (pas de blocage) si le bailleur bascule une
///   nature ajustable vers `recoverable` alors que ce n'est pas le défaut —
///   risque juridique décret n°87-713.
/// - La période de rattachement est dérivée de la date de dépense par
///   défaut, mais reste corrigeable — obligatoire si `recoverable`.
/// - Le justificatif est **recommandé mais non bloquant** (FEAT-041b,
///   décision produit #8) — voir [ExpenseReceiptField].
///
/// Séparé de [ExpenseFormPage] pour la testabilité unitaire.
class ExpenseForm extends StatefulWidget {
  const ExpenseForm({
    super.key,
    required this.formKey,
    required this.amountController,
    required this.leases,
    required this.propertyId,
    this.initialLeaseId,
    this.initialExpenseDate,
    this.initialNature,
    this.initialCategory,
    this.initialCategoryOverridden = false,
    this.initialPeriodStart,
    this.initialPeriodEnd,
    this.initialNotes,
    this.initialDocumentId,
    this.enabled = true,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController amountController;

  /// Baux disponibles pour ce bien (dropdown optionnel).
  final List<Lease> leases;

  /// Bien parent — transmis au champ justificatif (`createDocument`
  /// alternative au bail).
  final String propertyId;

  final String? initialLeaseId;
  final DateTime? initialExpenseDate;
  final ExpenseNature? initialNature;
  final ExpenseCategory? initialCategory;
  final bool initialCategoryOverridden;
  final DateTime? initialPeriodStart;
  final DateTime? initialPeriodEnd;
  final String? initialNotes;

  /// `documentId` du justificatif déjà attaché (édition) — voir
  /// [ExpenseReceiptField.existingDocumentId] (correctif review FEAT-041,
  /// finding 6).
  final String? initialDocumentId;
  final bool enabled;

  @override
  State<ExpenseForm> createState() => ExpenseFormWidgetState();
}

/// State public de [ExpenseForm] — exposé pour accès via [GlobalKey].
class ExpenseFormWidgetState extends State<ExpenseForm> {
  String? _leaseId;
  DateTime? _expenseDate;
  ExpenseNature? _nature;
  ExpenseCategory? _category;
  DateTime? _periodStart;
  DateTime? _periodEnd;
  final TextEditingController _notesController = TextEditingController();

  bool _amountTouched = false;
  bool _expenseDateTouched = false;
  bool _natureTouched = false;
  bool _periodStartTouched = false;
  bool _periodEndTouched = false;

  /// Vrai si l'utilisateur a explicitement ajusté la catégorie proposée par
  /// défaut pour la nature courante.
  bool _categoryManuallyOverridden = false;

  @override
  void initState() {
    super.initState();
    _leaseId = widget.initialLeaseId;
    _expenseDate = widget.initialExpenseDate;
    _nature = widget.initialNature;
    _category = widget.initialCategory ?? widget.initialNature?.defaultCategory;
    _categoryManuallyOverridden = widget.initialCategoryOverridden;
    _periodStart = widget.initialPeriodStart;
    _periodEnd = widget.initialPeriodEnd;
    _notesController.text = widget.initialNotes ?? '';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool get _isRecoverable => _category == ExpenseCategory.recoverable;

  /// Applique la nouvelle nature : présélectionne la catégorie par défaut et
  /// réinitialise l'override manuel (nouvelle nature = nouvelle décision).
  void _onNatureChanged(ExpenseNature? nature) {
    if (nature == null) return;
    setState(() {
      _nature = nature;
      _natureTouched = true;
      _category = nature.defaultCategory;
      _categoryManuallyOverridden = false;
      // Dérive la période depuis la date de dépense si pas encore saisie.
      if (_periodStart == null && _expenseDate != null) {
        _periodStart = DateTime(_expenseDate!.year, 1, 1);
      }
      if (_periodEnd == null && _expenseDate != null) {
        _periodEnd = DateTime(_expenseDate!.year, 12, 31);
      }
    });
  }

  /// Bascule la catégorie — **verrouillage dur** sur les natures verrouillées
  /// (le sélecteur n'apparaît même pas dans ce cas, cf. [build]).
  void _onCategoryChanged(ExpenseCategory? category) {
    if (category == null || _nature == null) return;
    setState(() {
      _category = category;
      _categoryManuallyOverridden = category != _nature!.defaultCategory;
    });
  }

  Future<void> _pickExpenseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: context.l10n.expensesFormExpenseDatePickerHelp,
    );
    if (picked != null && mounted) {
      setState(() {
        _expenseDate = picked;
        _expenseDateTouched = true;
        // Dérive la période par défaut (année civile) si pas déjà saisie.
        _periodStart ??= DateTime(picked.year, 1, 1);
        _periodEnd ??= DateTime(picked.year, 12, 31);
      });
    }
  }

  Future<void> _pickPeriodStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _periodStart ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: context.l10n.expensesFormPeriodStartPickerHelp,
    );
    if (picked != null && mounted) {
      setState(() {
        _periodStart = picked;
        _periodStartTouched = true;
      });
    }
  }

  Future<void> _pickPeriodEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _periodEnd ?? (_periodStart ?? DateTime.now()),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: context.l10n.expensesFormPeriodEndPickerHelp,
    );
    if (picked != null && mounted) {
      setState(() {
        _periodEnd = picked;
        _periodEndTouched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nature = _nature;

    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Bail (optionnel) ---
          DropdownButtonFormField<String?>(
            key: const Key('field_lease_id'),
            initialValue: _leaseId,
            decoration: InputDecoration(
              labelText: context.l10n.expensesFormLeaseFieldLabel,
              helperText: context.l10n.expensesFormLeaseFieldHelper,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(context.l10n.expensesFormNoLeaseOption),
              ),
              ...widget.leases.map(
                (l) => DropdownMenuItem<String?>(
                  value: l.id,
                  child: Text(
                    '${FrenchDate.format(l.startDate)} — '
                    '${_leaseStatusLabel(context, l.status)}',
                  ),
                ),
              ),
            ],
            onChanged: widget.enabled
                ? (id) => setState(() => _leaseId = id)
                : null,
          ),
          const SizedBox(height: 16),

          // --- Nature ---
          DropdownButtonFormField<ExpenseNature>(
            key: const Key('field_nature'),
            initialValue: nature,
            decoration: InputDecoration(
              labelText: context.l10n.expensesFormNatureFieldLabel,
              border: const OutlineInputBorder(),
              errorText: _natureTouched && nature == null
                  ? context.l10n.expensesFormNatureRequiredError
                  : null,
            ),
            items: ExpenseNature.values
                .map(
                  (n) => DropdownMenuItem(
                    value: n,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(n.icon, size: 18),
                        const SizedBox(width: 8),
                        Text(n.localizedLabel(context)),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: widget.enabled ? _onNatureChanged : null,
          ),
          const SizedBox(height: 8),

          // --- Catégorie (dérivée, verrouillée ou ajustable) ---
          if (nature != null) ...[
            _CategorySection(
              nature: nature,
              category: _category ?? nature.defaultCategory,
              overridden: _categoryManuallyOverridden,
              enabled: widget.enabled,
              onChanged: _onCategoryChanged,
            ),
            const SizedBox(height: 16),
          ],

          // --- Montant ---
          TextFormField(
            key: const Key('field_amount'),
            controller: widget.amountController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: context.l10n.expensesFormAmountFieldLabel,
              hintText: context.l10n.expensesFormAmountFieldHint,
              suffixText: '€',
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_amountTouched) setState(() {});
            },
            onEditingComplete: () {
              setState(() => _amountTouched = true);
              FocusScope.of(context).nextFocus();
            },
            validator: (v) {
              if (!_amountTouched) return null;
              return ExpenseFormValidators.validateAmount(v)?.message(context);
            },
          ),
          const SizedBox(height: 16),

          // --- Date de la dépense ---
          FormField<DateTime>(
            key: const Key('field_expense_date'),
            initialValue: _expenseDate,
            validator: (_) {
              if (!_expenseDateTouched) return null;
              return ExpenseFormValidators.validateExpenseDate(
                _expenseDate,
              )?.message(context);
            },
            builder: (state) => InkWell(
              onTap: widget.enabled ? _pickExpenseDate : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: context.l10n.expensesFormExpenseDateFieldLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  errorText: state.errorText,
                ),
                child: Text(
                  _expenseDate != null
                      ? FrenchDate.format(_expenseDate!)
                      : context.l10n.expensesFormSelectDatePlaceholder,
                  style: _expenseDate == null
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- Période de rattachement ---
          Text(
            _isRecoverable
                ? context.l10n.expensesFormPeriodSectionLabelRequired
                : context.l10n.expensesFormPeriodSectionLabelOptional,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isRecoverable
                ? context.l10n.expensesFormPeriodHelperRequired
                : context.l10n.expensesFormPeriodHelperDerived,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FormField<DateTime>(
                  key: const Key('field_period_start'),
                  initialValue: _periodStart,
                  validator: (_) {
                    if (!_periodStartTouched && !_isRecoverable) return null;
                    return ExpenseFormValidators.validatePeriodStart(
                      _periodStart,
                      isRecoverable: _isRecoverable,
                    )?.message(context);
                  },
                  builder: (state) => InkWell(
                    onTap: widget.enabled ? _pickPeriodStart : null,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText:
                            context.l10n.expensesFormPeriodStartFieldLabel,
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today_outlined),
                        errorText: state.errorText,
                      ),
                      child: Text(
                        _periodStart != null
                            ? FrenchDate.format(_periodStart!)
                            : '—',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FormField<DateTime>(
                  key: const Key('field_period_end'),
                  initialValue: _periodEnd,
                  validator: (_) {
                    if (!_periodEndTouched && !_isRecoverable) return null;
                    return ExpenseFormValidators.validatePeriodEnd(
                      _periodEnd,
                      _periodStart,
                      isRecoverable: _isRecoverable,
                    )?.message(context);
                  },
                  builder: (state) => InkWell(
                    onTap: widget.enabled ? _pickPeriodEnd : null,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: context.l10n.expensesFormPeriodEndFieldLabel,
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.calendar_today_outlined),
                        errorText: state.errorText,
                      ),
                      child: Text(
                        _periodEnd != null
                            ? FrenchDate.format(_periodEnd!)
                            : '—',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- Justificatif (recommandé, non bloquant) ---
          ExpenseReceiptField(
            propertyId: widget.propertyId,
            leaseId: _leaseId,
            enabled: widget.enabled,
            existingDocumentId: widget.initialDocumentId,
          ),
          const SizedBox(height: 16),

          // --- Notes ---
          TextFormField(
            key: const Key('field_notes'),
            controller: _notesController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: context.l10n.expensesFormNotesFieldLabel,
              hintText: context.l10n.expensesFormNotesFieldHint,
              border: const OutlineInputBorder(),
            ),
            maxLines: 3,
            maxLength: 2000,
            validator: (v) =>
                ExpenseFormValidators.validateNotes(v)?.message(context),
          ),
        ],
      ),
    );
  }

  /// Marque tous les champs obligatoires comme "touchés" et valide le formulaire.
  bool validateAll() {
    setState(() {
      _amountTouched = true;
      _expenseDateTouched = true;
      _natureTouched = true;
      _periodStartTouched = true;
      _periodEndTouched = true;
    });
    if (_nature == null) return false;
    return widget.formKey.currentState?.validate() ?? false;
  }

  String? get currentLeaseId => _leaseId;
  DateTime? get currentExpenseDate => _expenseDate;
  ExpenseNature? get currentNature => _nature;
  ExpenseCategory? get currentCategory => _category;
  bool get currentCategoryOverridden => _categoryManuallyOverridden;
  DateTime? get currentPeriodStart => _periodStart;
  DateTime? get currentPeriodEnd => _periodEnd;
  String get currentNotes => _notesController.text.trim();
}

/// Section catégorie — verrouillage dur ou ajustement avec avertissement.
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.nature,
    required this.category,
    required this.overridden,
    required this.enabled,
    required this.onChanged,
  });

  final ExpenseNature nature;
  final ExpenseCategory category;
  final bool overridden;
  final bool enabled;
  final ValueChanged<ExpenseCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (nature.isCategoryLocked) {
      // Verrouillage dur : pas de sélecteur, juste l'info + justification.
      return Container(
        key: const Key('category_locked_banner'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.expensesCategoryLockedLabel(
                      category.localizedLabel(context),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nature.localizedLockOrWarningExplanation(context),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Nature ajustable : sélecteur + avertissement si bascule vers
    // récupérable alors que le défaut est non-récupérable.
    final showWarning = overridden && category == ExpenseCategory.recoverable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ExpenseCategory>(
          key: const Key('field_category'),
          initialValue: category,
          decoration: InputDecoration(
            labelText: context.l10n.expensesFormCategoryFieldLabel,
            border: const OutlineInputBorder(),
          ),
          items: ExpenseCategory.values
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(c.localizedLabel(context)),
                ),
              )
              .toList(),
          onChanged: enabled ? onChanged : null,
        ),
        if (showWarning) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('category_override_warning'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.expensesCategoryOverrideWarningMessage(
                      nature.localizedLockOrWarningExplanation(context),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
