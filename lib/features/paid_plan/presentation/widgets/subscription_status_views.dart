import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/french_date.dart';

/// Vues de statut d'abonnement affichées par [SubscriptionSection]
/// (FEAT-044f) — extraites dans leur propre fichier pour respecter la
/// limite de 200 lignes par widget (CLAUDE.md).

/// Abonnement actif, renouvelable — bouton destructif « Résilier ».
class ActiveSubscriptionView extends StatelessWidget {
  const ActiveSubscriptionView({
    super.key,
    required this.expiresAt,
    required this.isBusy,
    required this.onCancel,
  });

  final DateTime? expiresAt;
  final bool isBusy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dateLabel = expiresAt != null ? FrenchDate.format(expiresAt!) : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.subscriptionActiveRenews(dateLabel),
          key: const Key('txt_subscription_status'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('btn_subscription_cancel'),
          onPressed: isBusy ? null : onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error),
          ),
          child: isBusy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.subscriptionCancelButton),
        ),
      ],
    );
  }
}

/// Résiliation déjà programmée — bouton non destructif « Réactiver ».
class ScheduledCancelView extends StatelessWidget {
  const ScheduledCancelView({
    super.key,
    required this.expiresAt,
    required this.isBusy,
    required this.onReactivate,
  });

  final DateTime? expiresAt;
  final bool isBusy;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dateLabel = expiresAt != null ? FrenchDate.format(expiresAt!) : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.subscriptionScheduledCancel(dateLabel),
          key: const Key('txt_subscription_status'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('btn_subscription_reactivate'),
          onPressed: isBusy ? null : onReactivate,
          child: isBusy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.subscriptionReactivateButton),
        ),
      ],
    );
  }
}
