import 'package:flutter/material.dart';

import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/utils/payment_form_validators.dart';
import '../../domain/payment_method.dart';
import 'payment_amount_warning.dart';

/// Champs partagés du formulaire paiement.
///
/// Utilisé dans [PaymentFormPage] pour la création et l'édition.
/// La validation est déclenchée inline à la perte de focus.
/// Utiliser un [GlobalKey<PaymentFormWidgetState>] pour appeler [validateAll].
///
/// [leaseTotalCents] : loyer + charges du bail (pré-rempli). Sert uniquement
/// à afficher le warning non bloquant (< ou > bail).
///
/// Séparé de [PaymentFormPage] pour la testabilité unitaire.
class PaymentForm extends StatefulWidget {
  const PaymentForm({
    super.key,
    required this.formKey,
    required this.rentController,
    required this.chargesController,
    required this.leaseTotalCents,
    required this.leaseRentCents,
    this.initialPeriodStart,
    this.initialPeriodEnd,
    this.initialPaidAt,
    this.initialPaymentMethod,
    this.initialNotes,
    this.initialReference,
    this.enabled = true,
    required this.onPeriodStartChanged,
    required this.onPeriodEndChanged,
    required this.onPaidAtChanged,
    required this.onPaymentMethodChanged,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController rentController;
  final TextEditingController chargesController;

  /// Loyer + charges du bail en centimes (pour le warning).
  final int leaseTotalCents;

  /// Loyer HC du bail en centimes (pour le warning).
  final int leaseRentCents;

  final DateTime? initialPeriodStart;
  final DateTime? initialPeriodEnd;
  final DateTime? initialPaidAt;
  final PaymentMethod? initialPaymentMethod;
  final String? initialNotes;
  final String? initialReference;
  final bool enabled;

  final void Function(DateTime?) onPeriodStartChanged;
  final void Function(DateTime?) onPeriodEndChanged;
  final void Function(DateTime?) onPaidAtChanged;
  final void Function(PaymentMethod?) onPaymentMethodChanged;

  @override
  State<PaymentForm> createState() => PaymentFormWidgetState();
}

/// State public de [PaymentForm] — exposé pour accès via [GlobalKey].
class PaymentFormWidgetState extends State<PaymentForm> {
  DateTime? _periodStart;
  DateTime? _periodEnd;
  DateTime? _paidAt;
  PaymentMethod? _paymentMethod;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  bool _periodStartTouched = false;
  bool _periodEndTouched = false;
  bool _paidAtTouched = false;
  bool _paymentMethodTouched = false;
  bool _rentTouched = false;
  bool _chargesTouched = false;

  @override
  void initState() {
    super.initState();
    _periodStart = widget.initialPeriodStart;
    _periodEnd = widget.initialPeriodEnd;
    _paidAt = widget.initialPaidAt;
    _paymentMethod = widget.initialPaymentMethod;
    _notesController.text = widget.initialNotes ?? '';
    _referenceController.text = widget.initialReference ?? '';
  }

  @override
  void dispose() {
    _notesController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _pickPeriodStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _periodStart ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Début de période',
    );
    if (picked != null && mounted) {
      setState(() {
        _periodStart = picked;
        _periodStartTouched = true;
      });
      widget.onPeriodStartChanged(picked);
    }
  }

  Future<void> _pickPeriodEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _periodEnd ?? (_periodStart ?? DateTime.now()),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Fin de période',
    );
    if (picked != null && mounted) {
      setState(() {
        _periodEnd = picked;
        _periodEndTouched = true;
      });
      widget.onPeriodEndChanged(picked);
    }
  }

  Future<void> _pickPaidAt() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Date de paiement',
    );
    if (picked != null && mounted) {
      setState(() {
        _paidAt = picked;
        _paidAtTouched = true;
      });
      widget.onPaidAtChanged(picked);
    }
  }

  /// Calcule l'avertissement montant à afficher (non bloquant).
  PaymentAmountWarningType? _computeWarning() {
    final rentCents = MoneyFormat.eurosToCents(widget.rentController.text);
    final chargesCents = MoneyFormat.eurosToCents(
      widget.chargesController.text,
    );
    if (rentCents == null || chargesCents == null) return null;
    final totalPaid = rentCents + chargesCents;
    if (totalPaid < widget.leaseTotalCents) {
      return PaymentAmountWarningType.below;
    }
    if (totalPaid > widget.leaseTotalCents) {
      return PaymentAmountWarningType.above;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = _computeWarning();

    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Loyer HC ---
          TextFormField(
            key: const Key('field_rent'),
            controller: widget.rentController,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: 'Loyer hors charges (€) *',
              hintText:
                  'Ex. : ${MoneyFormat.centsToInput(widget.leaseRentCents)}',
              suffixText: '€',
              border: const OutlineInputBorder(),
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
              return PaymentFormValidators.validateRentAmount(v);
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
              return PaymentFormValidators.validateChargesAmount(v);
            },
          ),
          const SizedBox(height: 8),

          // --- Warning montant (non bloquant) ---
          if (warning != null) PaymentAmountWarning(type: warning),
          const SizedBox(height: 8),

          // --- Mode de paiement ---
          FormField<PaymentMethod>(
            key: const Key('field_payment_method'),
            initialValue: _paymentMethod,
            validator: (_) {
              if (!_paymentMethodTouched) return null;
              return PaymentFormValidators.validatePaymentMethod(
                _paymentMethod,
              );
            },
            builder: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: _paymentMethod,
                  decoration: InputDecoration(
                    labelText: 'Mode de paiement *',
                    border: const OutlineInputBorder(),
                    errorText: state.errorText,
                  ),
                  items: PaymentMethod.values
                      .map(
                        (m) => DropdownMenuItem(value: m, child: Text(m.label)),
                      )
                      .toList(),
                  onChanged: widget.enabled
                      ? (m) {
                          setState(() {
                            _paymentMethod = m;
                            _paymentMethodTouched = true;
                          });
                          widget.onPaymentMethodChanged(m);
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // --- Référence ---
          TextFormField(
            key: const Key('field_reference'),
            controller: _referenceController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Référence (n° virement / chèque, optionnel)',
              hintText: 'Ex. : VIR-2024-001',
              helperText: 'Pour rapprochement comptable',
              border: OutlineInputBorder(),
            ),
            maxLength: 100,
            validator: (v) {
              if (v == null || v.isEmpty) return null;
              if (v.trim().isEmpty) {
                return 'La référence ne peut pas être uniquement des espaces.';
              }
              if (v.length > 100) {
                return 'La référence ne peut pas dépasser 100 caractères.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // --- Début de période ---
          FormField<DateTime>(
            key: const Key('field_period_start'),
            initialValue: _periodStart,
            validator: (_) {
              if (!_periodStartTouched) return null;
              return PaymentFormValidators.validatePeriodStart(_periodStart);
            },
            builder: (state) => InkWell(
              onTap: widget.enabled ? _pickPeriodStart : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Début de période *',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  errorText: state.errorText,
                ),
                child: Text(
                  _periodStart != null
                      ? FrenchDate.format(_periodStart!)
                      : 'Sélectionner une date',
                  style: _periodStart == null
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- Fin de période ---
          FormField<DateTime>(
            key: const Key('field_period_end'),
            initialValue: _periodEnd,
            validator: (_) {
              if (!_periodEndTouched) return null;
              return PaymentFormValidators.validatePeriodEnd(
                _periodEnd,
                _periodStart,
              );
            },
            builder: (state) => InkWell(
              onTap: widget.enabled ? _pickPeriodEnd : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Fin de période *',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  errorText: state.errorText,
                ),
                child: Text(
                  _periodEnd != null
                      ? FrenchDate.format(_periodEnd!)
                      : 'Sélectionner une date',
                  style: _periodEnd == null
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- Date de paiement ---
          FormField<DateTime>(
            key: const Key('field_paid_at'),
            initialValue: _paidAt,
            validator: (_) {
              if (!_paidAtTouched) return null;
              return PaymentFormValidators.validatePaidAt(_paidAt);
            },
            builder: (state) => InkWell(
              onTap: widget.enabled ? _pickPaidAt : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date de paiement *',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  errorText: state.errorText,
                ),
                child: Text(
                  _paidAt != null
                      ? FrenchDate.format(_paidAt!)
                      : 'Sélectionner une date',
                  style: _paidAt == null
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- Notes ---
          TextFormField(
            key: const Key('field_notes'),
            controller: _notesController,
            enabled: widget.enabled,
            decoration: const InputDecoration(
              labelText: 'Notes (optionnel)',
              hintText: 'Ex. : paiement en deux fois',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            maxLength: 500,
            validator: (v) => PaymentFormValidators.validateNotes(v),
          ),
        ],
      ),
    );
  }

  /// Marque tous les champs obligatoires comme "touchés" et valide le formulaire.
  ///
  /// Appelé par [PaymentFormPage] lors du tap sur "Soumettre".
  bool validateAll() {
    setState(() {
      _rentTouched = true;
      _chargesTouched = true;
      _paymentMethodTouched = true;
      _periodStartTouched = true;
      _periodEndTouched = true;
      _paidAtTouched = true;
    });
    return widget.formKey.currentState?.validate() ?? false;
  }

  /// Retourne la date de début de période courante.
  DateTime? get currentPeriodStart => _periodStart;

  /// Retourne la date de fin de période courante.
  DateTime? get currentPeriodEnd => _periodEnd;

  /// Retourne la date de paiement courante.
  DateTime? get currentPaidAt => _paidAt;

  /// Retourne le mode de paiement courant.
  PaymentMethod? get currentPaymentMethod => _paymentMethod;

  /// Retourne les notes saisies.
  String get currentNotes => _notesController.text.trim();

  /// Retourne la référence saisie (n° virement / chèque).
  String get currentReference => _referenceController.text.trim();
}
