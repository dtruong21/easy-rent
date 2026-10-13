import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/french_date.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/archive_confirm_dialog.dart';
import '../../../receipts/presentation/widgets/generate_receipt_button.dart';
import '../../domain/payment.dart';
import '../payment_method_l10n.dart';

/// Tile d'un paiement dans la liste de la fiche bail.
///
/// Affiche : période, montant total, mode de paiement.
/// Actions : bouton modifier + bouton archiver + bouton générer quittance.
class PaymentListTile extends StatelessWidget {
  const PaymentListTile({
    super.key,
    required this.payment,
    required this.leaseId,
    required this.onEdit,
    required this.onArchive,
  });

  final Payment payment;

  /// Identifiant du bail parent — requis pour [GenerateReceiptButton].
  final String leaseId;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final periodLabel =
        '${FrenchDate.format(payment.periodStart)} – ${FrenchDate.format(payment.periodEnd)}';
    final amountLabel = MoneyFormat.formatEurosFromCents(
      payment.totalAmountCents,
    );

    final subtitleParts = [
      PaymentMethodL10n(payment.paymentMethod).label(context),
      if (payment.reference != null && payment.reference!.isNotEmpty)
        context.l10n.paymentsListReferencePrefix(payment.reference!),
      amountLabel,
    ];

    return ListTile(
      key: Key('payment_tile_${payment.id}'),
      title: Text(periodLabel, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        subtitleParts.join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GenerateReceiptButton(paymentId: payment.id, leaseId: leaseId),
          // Modifier / Archiver : menu ⋮ à libellés (comme les cartes de
          // liste) plutôt que deux icônes muettes (recette iOS, #197).
          PopupMenuButton<_PaymentAction>(
            key: Key('payment_menu_${payment.id}'),
            icon: const Icon(Icons.more_vert),
            tooltip: context.l10n.commonMoreActions,
            onSelected: (action) => switch (action) {
              _PaymentAction.edit => onEdit(),
              _PaymentAction.archive => _confirmArchive(context),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                key: Key('btn_edit_payment_${payment.id}'),
                value: _PaymentAction.edit,
                child: Text(context.l10n.commonEdit),
              ),
              PopupMenuItem(
                key: Key('btn_archive_payment_${payment.id}'),
                value: _PaymentAction.archive,
                child: Text(
                  context.l10n.paymentsArchiveTooltip,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context) async {
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (_) => ArchiveConfirmDialog(
        title: l10n.paymentsArchiveDialogTitle,
        entityLabel: l10n.paymentsArchiveDialogEntityLabel,
        // Un paiement n'a pas de distinction "bail actif" (hasActiveLease
        // toujours false ci-dessous) — même message pour les deux variantes.
        standardMessage: l10n.paymentsArchiveDialogMessage,
        activeLeaseMessage: l10n.paymentsArchiveDialogMessage,
        hasActiveLease: false,
        onConfirm: onArchive,
      ),
    );
  }
}

enum _PaymentAction { edit, archive }
