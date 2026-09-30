import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/plan_level.dart';
import '../../../paid_plan/presentation/pro_pricing_cta.dart' show mobileStores;

/// Avertissement « abonnement » de `/profile/delete-account`, affiché avant la
/// confirmation, sur toutes les plateformes (exigence stores : supprimer le
/// compte ne doit pas laisser croire que la facturation s'arrête).
///
/// Lit le même snapshot que `SubscriptionSection` ([landlordTierProvider]) :
/// - palier gratuit (ou snapshot non résolu) → rien ;
/// - abonnement via store (`proStore` ∈ {app_store, play_store}) → la
///   suppression ne résilie PAS l'abonnement, à résilier dans les réglages du
///   store ;
/// - abonnement web (Stripe — `proStore` `null`/`web`/inconnu, même règle que
///   `SubscriptionSection`) → résilié immédiatement, sans remboursement.
class DeleteAccountSubscriptionNotice extends ConsumerWidget {
  const DeleteAccountSubscriptionNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(landlordTierProvider).valueOrNull;
    if (snapshot == null || !snapshot.plan.atLeast(PlanLevel.pro)) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isStoreSubscription = mobileStores.contains(snapshot.proStore);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        key: Key(
          isStoreSubscription
              ? 'box_delete_account_store_subscription_warning'
              : 'box_delete_account_web_subscription_notice',
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isStoreSubscription
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isStoreSubscription
                    ? l10n.deleteAccountStoreSubscriptionWarning
                    : l10n.deleteAccountWebSubscriptionNotice,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
