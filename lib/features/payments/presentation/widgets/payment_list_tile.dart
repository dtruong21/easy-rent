import 'package:flutter/material.dart';

import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/archive_confirm_dialog.dart';
import '../../domain/payment.dart';

/// Tile d'un paiement dans la liste de la fiche bail.
///
/// Affiche : période, montant total, mode de paiement.
/// Actions : bouton modifier (navigation) + bouton archiver (confirmation).
class PaymentListTile extends StatelessWidget {
  const PaymentListTile({
    super.key,
    required this.payment,
    required this.onEdit,
    required this.onArchive,
  });

  final Payment payment;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final periodLabel =
        '${_formatDate(payment.periodStart)} – ${_formatDate(payment.periodEnd)}';
    final amountLabel = MoneyFormat.formatEurosFromCents(
      payment.totalAmountCents,
    );

    return ListTile(
      key: Key('payment_tile_${payment.id}'),
      title: Text(periodLabel, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        '${payment.paymentMethod.label} · $amountLabel',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('btn_edit_payment_${payment.id}'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier',
            onPressed: onEdit,
          ),
          IconButton(
            key: Key('btn_archive_payment_${payment.id}'),
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Archiver',
            color: theme.colorScheme.error,
            onPressed: () => _confirmArchive(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ArchiveConfirmDialog(
        title: 'Archiver ce paiement ?',
        entityLabel: 'Ce paiement',
        standardMessage:
            'Voulez-vous archiver ce paiement ? '
            "Il n'apparaîtra plus dans la liste.",
        activeLeaseMessage:
            'Voulez-vous archiver ce paiement ? '
            "Il n'apparaîtra plus dans la liste.",
        hasActiveLease: false,
        onConfirm: onArchive,
      ),
    );
  }
}
