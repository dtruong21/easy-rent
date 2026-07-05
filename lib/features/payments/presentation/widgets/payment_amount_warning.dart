import 'package:flutter/material.dart';

/// Type de warning pour le montant du paiement.
enum PaymentAmountWarningType {
  /// Montant inférieur au loyer du bail.
  below,

  /// Montant supérieur au loyer du bail.
  above,
}

/// Banner non bloquante affichée quand le montant saisi diffère du bail.
///
/// - Montant inférieur : "Montant inférieur au bail — un reçu sera émis (pas
///   une quittance libératoire)."
/// - Montant supérieur : "Montant supérieur au bail — vérifiez s'il s'agit
///   d'une régularisation."
///
/// Non bloquante : la soumission reste possible.
class PaymentAmountWarning extends StatelessWidget {
  const PaymentAmountWarning({super.key, required this.type});

  final PaymentAmountWarningType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, message, color) = switch (type) {
      PaymentAmountWarningType.below => (
        Icons.info_outline,
        "Montant inférieur au bail — un reçu sera émis (pas une quittance libératoire).",
        theme.colorScheme.tertiary,
      ),
      PaymentAmountWarningType.above => (
        Icons.warning_amber_outlined,
        "Montant supérieur au bail — vérifiez s'il s'agit d'une régularisation.",
        theme.colorScheme.error,
      ),
    };

    return Container(
      key: switch (type) {
        PaymentAmountWarningType.below => const Key('warning_amount_below'),
        PaymentAmountWarningType.above => const Key('warning_amount_above'),
      },
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
