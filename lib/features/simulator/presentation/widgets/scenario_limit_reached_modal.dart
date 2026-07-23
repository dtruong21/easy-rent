import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../auth/domain/subscription_tier.dart';

/// Affiche la modal bloquante de limite de scénarios atteinte.
///
/// - `tier == anonymous` : CTA « Créer un compte » (jusqu'à 3 scénarios).
/// - `tier == free` : CTA « Passer à Pro » → `/pro` (checkout Stripe).
Future<void> showScenarioLimitReachedModal(
  BuildContext context, {
  required SubscriptionTier tier,
}) {
  assert(
    tier != SubscriptionTier.paid,
    'showScenarioLimitReachedModal ne doit jamais être appelée pour un '
    'tier paid (illimité — canSaveAnotherScenarioProvider est déjà true).',
  );
  return showDialog<void>(
    context: context,
    builder: (context) => _ScenarioLimitReachedDialog(tier: tier),
  );
}

class _ScenarioLimitReachedDialog extends StatelessWidget {
  const _ScenarioLimitReachedDialog({required this.tier});

  final SubscriptionTier tier;

  @override
  Widget build(BuildContext context) {
    final isAnonymous = tier == SubscriptionTier.anonymous;
    final l10n = context.l10n;

    return AlertDialog(
      key: const Key('scenario_limit_reached_modal'),
      title: Text(
        isAnonymous
            ? l10n.simulatorLimitReachedTitleAnonymous
            : l10n.simulatorLimitReachedTitleFree,
      ),
      content: Text(
        isAnonymous
            ? l10n.simulatorLimitReachedContentAnonymous
            : l10n.simulatorLimitReachedContentFree,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.simulatorLimitReachedLaterButton),
        ),
        if (isAnonymous)
          FilledButton(
            key: const Key('scenario_limit_signup_cta'),
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/signup');
            },
            child: Text(l10n.simulatorLimitReachedSignupButton),
          )
        else
          FilledButton(
            key: const Key('scenario_limit_upgrade_cta'),
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/pro');
            },
            child: Text(l10n.proUpgradeButton),
          ),
      ],
    );
  }
}

