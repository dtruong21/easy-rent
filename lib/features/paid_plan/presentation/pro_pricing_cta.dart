/// Construction pure des CTA de la page `/pro` (FEAT-056 PR-6) — extrait de
/// ProPricingPage pour respecter la limite de 200 lignes par widget
/// (CLAUDE.md). Chaque fonction ne fait QUE composer un [Widget] à partir de
/// données déjà résolues ; les actions réseau (checkout, change_plan,
/// notify-me) et l'état de chargement restent dans l'État de la page, qui
/// passe ici des callbacks déjà préparés.
library;

import 'package:flutter/material.dart';

import '../../../core/config/env.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../../auth/domain/plan_entitlement.dart';
import '../../auth/domain/plan_level.dart';
import '../../auth/domain/plan_matrix.g.dart';
import '../../auth/domain/subscription_tier.dart';
import 'widgets/plan_level_label.dart';

/// Origines d'abonnement gérées par le store natif — changement de palier
/// impossible depuis le web (FEAT-056 §4.4). Liste UNIQUE, partagée par
/// `SubscriptionSection` et `DeleteAccountSubscriptionNotice`.
const mobileStores = {'app_store', 'play_store'};

bool isCurrentLevel(PlanEntitlement plan, String levelId) =>
    plan.tier == SubscriptionTier.paid && plan.level?.id == levelId;

/// CTA de la carte Gratuit : « Votre offre actuelle » (désactivé) si
/// [plan] est déjà gratuit, sinon rien (un abonné payant n'a rien à faire
/// sur cette carte — le downgrade vers Gratuit passe par la résiliation,
/// pas par `/pro`).
Widget buildFreeCta(BuildContext context, PlanEntitlement plan) {
  final l10n = context.l10n;
  if (plan.tier == SubscriptionTier.paid) return const SizedBox.shrink();
  return FilledButton.tonal(
    key: const Key('btn_plan_current_free'),
    onPressed: null,
    child: Text(
      plan.tier == SubscriptionTier.free
          ? l10n.proCurrentPlanLabel
          : l10n.proPricingFreeCta,
    ),
  );
}

/// Badge « Bientôt disponible » — jamais affiché sur le palier déjà détenu
/// (cf. [isCurrentLevel]), ni sur un palier `purchasable` tant que le gate
/// global [Env.subscriptionsEnabled] est ouvert.
Widget? buildComingSoonBadge(
  BuildContext context,
  PlanEntitlement plan,
  PlanLevelSpec spec,
) {
  if (isCurrentLevel(plan, spec.id)) return null;
  if (Env.subscriptionsEnabled && spec.purchasable) return null;
  final theme = Theme.of(context);
  return Container(
    key: Key('badge_plan_coming_soon_${spec.id}'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      context.l10n.proComingSoonBadge,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSecondaryContainer,
      ),
    ),
  );
}

/// CTA d'un palier payant — ordre de décision documenté en ligne (FEAT-056
/// §8.1) : offre déjà détenue > gate global > gate par palier > store mobile
/// > changement de palier (déjà payant) > checkout (pas encore payant).
///
/// [onCheckout]/[onChangePlan]/[onSwitchPeriod] sont invoqués uniquement
/// quand le palier cible est `purchasable` **et** le gate global est ouvert —
/// jamais de chemin de paiement construit pour un palier non achetable
/// (critère testable, `test/widget/pro_pricing_page_test.dart`). [annual] =
/// position de l'interrupteur mensuel/annuel de la page. [currentPeriod] =
/// périodicité facturée à l'abonné (`'monthly'`/`'annual'`), `null` tant
/// qu'elle est inconnue : le passage mensuel ↔ annuel n'est proposé que vers
/// l'AUTRE périodicité.
/// [subscriptionsEnabled] = gate global, injectable pour les tests (figé à
/// `false` dans `flutter test`).
Widget buildPaidLevelCta(
  BuildContext context, {
  required PlanEntitlement plan,
  required String? proStore,
  required PlanLevelSpec spec,
  required bool checkoutLoading,
  required bool planChangeLoading,
  required bool notifyLoading,
  required bool notified,
  required bool annual,
  required String? currentPeriod,
  required VoidCallback onCheckout,
  required void Function(bool isUpgrade) onChangePlan,
  required VoidCallback onSwitchPeriod,
  required VoidCallback onNotifyMe,
  bool subscriptionsEnabled = Env.subscriptionsEnabled,
}) {
  final l10n = context.l10n;
  final levelId = spec.id;
  final level = PlanLevel.values.firstWhere((l) => l.id == levelId);

  // 1. Déjà sur ce palier : PRIME sur tout gate — un abonné doit toujours
  //    voir son offre active, jamais un « bientôt disponible » sur le
  //    palier qu'il a déjà payé. Abonné web, vente ouverte : il peut aussi
  //    passer ce palier à l'autre périodicité, celle de l'interrupteur —
  //    jamais vers celle qu'il a déjà, ni tant que la sienne est inconnue.
  if (plan.tier == SubscriptionTier.paid && plan.level == level) {
    final current = FilledButton.tonal(
      key: Key('btn_plan_current_$levelId'),
      onPressed: null,
      child: Text(l10n.proCurrentPlanLabel),
    );
    final canSwitchPeriod =
        subscriptionsEnabled &&
        spec.purchasable &&
        !mobileStores.contains(proStore) &&
        currentPeriod != null &&
        currentPeriod != (annual ? 'annual' : 'monthly');
    if (!canSwitchPeriod) return current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        current,
        const SizedBox(height: 8),
        OutlinedButton(
          key: Key('btn_plan_switch_period_$levelId'),
          onPressed: planChangeLoading ? null : onSwitchPeriod,
          child: Text(
            annual
                ? l10n.proSwitchToAnnualButton
                : l10n.proSwitchToMonthlyButton,
          ),
        ),
      ],
    );
  }
  // 2. Gate global : Env.subscriptionsEnabled == false ferme les 3 offres
  //    payantes, Pro inclus (prime sur `purchasable`, plan §8.1).
  if (!subscriptionsEnabled) {
    return buildComingSoonCta(
      context,
      levelId: levelId,
      showPausedNotice: true,
      isLoading: notifyLoading,
      isNotified: notified,
      onNotifyMe: onNotifyMe,
    );
  }
  // 3. Gate par palier : non ouvert à la vente (Max/Ultra au lancement).
  if (!spec.purchasable) {
    return buildComingSoonCta(
      context,
      levelId: levelId,
      showPausedNotice: false,
      isLoading: notifyLoading,
      isNotified: notified,
      onNotifyMe: onNotifyMe,
    );
  }
  // 4. Abonné via un store mobile : changement de palier hors web.
  final isMobileStore = mobileStores.contains(proStore);
  if (plan.tier == SubscriptionTier.paid && isMobileStore) {
    return Text(
      l10n.subscriptionManageOnStore,
      key: Key('txt_plan_manage_on_store_$levelId'),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
  // 5. Déjà payant sur un autre palier web → changement en libre-service.
  if (plan.tier == SubscriptionTier.paid) {
    final isUpgrade = level.rank > plan.level!.rank;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        key: Key('btn_plan_change_$levelId'),
        onPressed: planChangeLoading ? null : () => onChangePlan(isUpgrade),
        child: Text(
          isUpgrade
              ? l10n.proUpgradeToLevel(level.label(context))
              : l10n.proDowngradeToLevel(level.label(context)),
        ),
      ),
    );
  }
  // 6. Pas encore payant → checkout.
  final label = levelId == 'pro'
      ? l10n.proSubscribeButton
      : l10n.proUpgradeToLevel(level.label(context));
  return SizedBox(
    width: double.infinity,
    child: FilledButton(
      key: Key('btn_plan_subscribe_$levelId'),
      onPressed: checkoutLoading ? null : onCheckout,
      child: checkoutLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    ),
  );
}

/// Bloc « bientôt disponible » : notice explicative (uniquement pour le gate
/// global, [showPausedNotice]) + bouton de capture d'intérêt taguée par
/// palier.
Widget buildComingSoonCta(
  BuildContext context, {
  required String levelId,
  required bool showPausedNotice,
  required bool isLoading,
  required bool isNotified,
  required VoidCallback onNotifyMe,
}) {
  final l10n = context.l10n;
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showPausedNotice) ...[
        Text(
          l10n.proSubscriptionsPausedNotice,
          key: Key('txt_plan_paused_notice_$levelId'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
      ],
      FilledButton.tonal(
        key: Key('btn_plan_notify_$levelId'),
        onPressed: (isLoading || isNotified) ? null : onNotifyMe,
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                isNotified
                    ? l10n.proPricingNotifiedAtLaunchLabel
                    : l10n.proPricingNotifyAtLaunchButton,
              ),
      ),
    ],
  );
}
