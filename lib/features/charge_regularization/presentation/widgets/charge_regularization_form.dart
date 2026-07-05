import 'package:flutter/material.dart';

import '../../../../core/utils/money_format.dart';
import '../../../../core/utils/money_validators.dart';
import '../../../payments/domain/payment.dart';
import '../../application/charge_provisions_calculator.dart';
import '../../domain/charge_regularization_balance.dart';
import 'charge_regularization_balance_summary.dart';
import 'charge_regularization_period_picker.dart';

/// Corps du formulaire de régularisation — période de référence, provisions
/// calculées automatiquement, dépenses réelles saisies manuellement, solde
/// en direct.
///
/// Extrait de [ChargeRegularizationDialog] pour lisibilité (règle
/// "widgets < 200 lignes"). Reste purement présentationnel — tout l'état vit
/// dans le parent (`ChargeRegularizationDialog`), remonté via callbacks.
class ChargeRegularizationForm extends StatelessWidget {
  const ChargeRegularizationForm({
    super.key,
    required this.periodStart,
    required this.periodEnd,
    required this.payments,
    required this.actualExpensesController,
    required this.actualExpensesCents,
    required this.onPeriodStartChanged,
    required this.onPeriodEndChanged,
    required this.onActualExpensesChanged,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final List<Payment> payments;
  final TextEditingController actualExpensesController;
  final int actualExpensesCents;
  final void Function(DateTime) onPeriodStartChanged;
  final void Function(DateTime) onPeriodEndChanged;
  final void Function(int) onActualExpensesChanged;

  /// Vrai si la période de référence est inversée ou nulle (fin <= début) —
  /// produirait un avis légal incohérent et un calcul de provisions faux
  /// (correctif review FEAT-029).
  bool get isPeriodInvalid => !periodEnd.isAfter(periodStart);

  @override
  Widget build(BuildContext context) {
    final provisionsCents = sumChargeProvisionsForPeriod(
      payments: payments,
      referenceStart: periodStart,
      referenceEnd: periodEnd,
    );
    final balance = ChargeRegularizationBalance(
      periodStart: periodStart,
      periodEnd: periodEnd,
      provisionsCollectedCents: provisionsCents,
      actualExpensesCents: actualExpensesCents,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Comparez les provisions encaissées aux dépenses réelles '
          'justifiées par le syndic pour calculer le solde de '
          'régularisation.',
        ),
        const SizedBox(height: 16),
        ChargeRegularizationPeriodPicker(
          label: 'Début de période',
          date: periodStart,
          onPick: onPeriodStartChanged,
        ),
        const SizedBox(height: 12),
        ChargeRegularizationPeriodPicker(
          label: 'Fin de période',
          date: periodEnd,
          onPick: onPeriodEndChanged,
          // Empêche de choisir une fin antérieure ou égale au début dès
          // l'ouverture du picker — n'empêche pas à lui seul l'incohérence
          // si `periodStart` est repoussé APRÈS coup au-delà d'un
          // `periodEnd` déjà choisi (le contrat `minDate` du picker ne se
          // réévalue qu'à sa prochaine ouverture) : c'est pourquoi
          // `errorText` ci-dessous couvre aussi ce cas.
          minDate: periodStart.add(const Duration(days: 1)),
          errorText: isPeriodInvalid
              ? 'La date de fin doit être postérieure à la date de début'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('field_actual_expenses'),
          controller: actualExpensesController,
          decoration: const InputDecoration(
            labelText: 'Dépenses réelles (€) *',
            hintText: 'Montant justifié par le décompte syndic',
            suffixText: '€',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) =>
              onActualExpensesChanged(MoneyFormat.eurosToCents(v) ?? 0),
          validator: (v) => MoneyValidators.validateChargesAmount(
            v,
            requiredMessage:
                'Le montant des dépenses réelles est obligatoire '
                '(saisir 0 si aucune)',
          ),
        ),
        const SizedBox(height: 16),
        ChargeRegularizationBalanceSummary(balance: balance),
      ],
    );
  }
}
