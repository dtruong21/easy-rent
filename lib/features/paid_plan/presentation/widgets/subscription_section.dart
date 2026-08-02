import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/french_date.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/plan_level.dart';
import '../../../profile/presentation/widgets/section_header.dart';
import '../../application/manage_subscription_controller.dart';
import '../../data/subscription_repository.dart';
import 'plan_level_label.dart';
import 'subscription_cancel_dialog.dart';
import 'subscription_status_views.dart';

/// Origines d'abonnement gérées par le store natif (résiliation IAP hors
/// périmètre v1, cf. plan FEAT-044f §Hors périmètre — deep-link système
/// `showManageSubscriptions`, non implémenté ici).
const _mobileStores = {'app_store', 'play_store'};

/// Section « Abonnement Baillan Pro » de `/profile` (FEAT-044f).
///
/// S'auto-masque pour tout compte n'ayant pas au moins le palier
/// [PlanLevel.pro] — [ProfilePage] l'insère donc sans condition (même
/// convention que `ProfileCrashReportingSection`).
///
/// Rendu selon [LandlordTierSnapshot] (`landlordTierProvider`) :
/// - `proStore` ∈ {app_store, play_store} → message info, pas de bouton ;
/// - web (store `null`/inconnu inclus, cf. plan §R5 — ne jamais cacher le
///   chemin de résiliation à un abonné web) + `proWillRenew != false` →
///   « Actif — renouvellement le … » + bouton destructif « Résilier » →
///   dialog de confirmation (récapitulatif art. L215-1-1) ;
/// - web + `proWillRenew == false` → « Pro jusqu'au …, puis Gratuit » +
///   bouton « Réactiver » (pas de confirmation — action symétrique, non
///   destructive).
class SubscriptionSection extends ConsumerWidget {
  const SubscriptionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(landlordTierProvider).valueOrNull;
    if (!(snapshot?.plan.atLeast(PlanLevel.pro) ?? false)) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final isBusy = ref.watch(manageSubscriptionControllerProvider).isLoading;
    final isMobileStore = _mobileStores.contains(snapshot?.proStore);
    // Grandfathering I3 (FEAT-056) : `level` est non-null dès lors que
    // `atLeast(PlanLevel.pro)` a déjà validé l'accès à cette section (le
    // garde ci-dessus retourne `SizedBox.shrink()` sinon).
    final levelLabel = snapshot!.plan.level!.label(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.subscriptionSectionTitle(levelLabel)),
        const SizedBox(height: 8),
        if (isMobileStore)
          Text(
            l10n.subscriptionManageOnStore,
            key: const Key('txt_subscription_manage_on_store'),
          )
        else if (snapshot.proWillRenew == false)
          ScheduledCancelView(
            expiresAt: snapshot.proExpiresAt,
            isBusy: isBusy,
            onReactivate: () => _reactivate(context, ref),
            levelLabel: levelLabel,
          )
        else
          ActiveSubscriptionView(
            expiresAt: snapshot.proExpiresAt,
            isBusy: isBusy,
            onCancel: () => _confirmCancel(context, ref),
          ),
        if (!isMobileStore) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('btn_subscription_change_plan'),
            onPressed: () => context.go('/pro'),
            child: Text(l10n.subscriptionChangePlanButton),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final snapshot = ref.read(landlordTierProvider).valueOrNull;
    final expiresAt = snapshot?.proExpiresAt;
    // Fallback '—' (aligné sur les vues de statut) plutôt que '' : évite une
    // phrase tronquée « jusqu'au , puis… » dans le cas edge proExpiresAt == null.
    final dateLabel = expiresAt != null ? FrenchDate.format(expiresAt) : '—';
    final levelLabel = snapshot?.plan.level?.label(context) ?? '';

    final confirmed = await showSubscriptionCancelDialog(
      context,
      dateLabel: dateLabel,
      levelLabel: levelLabel,
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await ref
        .read(manageSubscriptionControllerProvider.notifier)
        .cancel();
    if (!context.mounted) return;
    _showResult(
      context,
      ref,
      ok: ok,
      successMessage: context.l10n.subscriptionCancelSuccess,
    );
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    final ok = await ref
        .read(manageSubscriptionControllerProvider.notifier)
        .reactivate();
    if (!context.mounted) return;
    _showResult(
      context,
      ref,
      ok: ok,
      successMessage: context.l10n.subscriptionReactivateSuccess,
    );
  }

  void _showResult(
    BuildContext context,
    WidgetRef ref, {
    required bool ok,
    required String successMessage,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final message = ok
        ? successMessage
        : ref.read(manageSubscriptionControllerProvider).error
              is NoActiveWebSubscriptionException
        ? l10n.subscriptionErrorNoWebSub
        : l10n.subscriptionErrorGeneric;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: Key(
          ok ? 'snackbar_subscription_success' : 'snackbar_subscription_error',
        ),
        content: Text(message),
        backgroundColor: ok ? null : theme.colorScheme.errorContainer,
      ),
    );
  }
}
