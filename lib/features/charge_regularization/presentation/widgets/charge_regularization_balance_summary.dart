import 'package:flutter/material.dart';

import '../../../../core/ui/cards/status_pill.dart';
import '../../../../core/ui/cards/status_pill_tone.dart';
import '../../../../core/utils/money_format.dart';
import '../../domain/charge_regularization_balance.dart';

/// Résumé en direct du solde calculé — provisions, dépenses réelles, solde
/// signé avec libellé explicite.
///
/// Extrait de [ChargeRegularizationDialog] pour lisibilité (règle
/// "widgets < 200 lignes").
class ChargeRegularizationBalanceSummary extends StatelessWidget {
  const ChargeRegularizationBalanceSummary({super.key, required this.balance});

  final ChargeRegularizationBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = switch (balance.direction) {
      ChargeRegularizationBalanceDirection.dueByTenant =>
        StatusPillTone.warning,
      ChargeRegularizationBalanceDirection.dueToTenant => StatusPillTone.info,
      ChargeRegularizationBalanceDirection.balanced => StatusPillTone.neutral,
    };

    return Container(
      key: const Key('charge_regularization_balance_summary'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(
            theme,
            'Provisions encaissées',
            MoneyFormat.formatEurosFromCents(balance.provisionsCollectedCents),
          ),
          const SizedBox(height: 4),
          _row(
            theme,
            'Dépenses réelles',
            MoneyFormat.formatEurosFromCents(balance.actualExpensesCents),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Solde',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                MoneyFormat.formatEurosFromCents(balance.balanceAbsCents),
                key: const Key('charge_regularization_balance_amount'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StatusPill(
            key: const Key('charge_regularization_balance_label'),
            label: balance.labelFr,
            tone: tone,
          ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
