import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/store_billing.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/domain/plan_entitlement.dart';
import '../../../auth/domain/plan_level.dart';
import '../../../auth/domain/subscription_tier.dart';
import '../../../paid_plan/presentation/widgets/plan_level_label.dart';

/// Affiche la modal bloquante de limite de scénarios atteinte.
///
/// - `tier == anonymous` : CTA « Créer un compte » (jusqu'à 3 scénarios).
/// - `tier == free` : CTA « Passer à Pro » → `/pro` (checkout Stripe).
/// - `tier == paid` (Pro ou Max, plafonnés depuis FEAT-056 — seul Ultra est
///   illimité) : CTA « Passer à {palier suivant} » → `/pro`, palier suivant
///   dérivé du rang de l'enum [PlanLevel], jamais codé en dur.
///
/// Dans les apps iOS/Android ([isStoreApp]), le CTA vers `/pro` disparaît (aucun
/// achat hors achat intégré) : la modale garde son message (aucun prix n'y
/// figure) et sa fermeture, libellée « Fermer » (neutre) — « Plus tard »
/// renverrait à un achat que l'app ne propose pas. Le cas anonyme garde son CTA
/// « Créer un compte », donc « Plus tard ».
Future<void> showScenarioLimitReachedModal(
  BuildContext context, {
  required PlanEntitlement plan,
}) {
  assert(
    !plan.atLeast(PlanLevel.ultra),
    'showScenarioLimitReachedModal ne doit jamais être appelée pour un '
    'compte Ultra (illimité — canSaveAnotherScenarioProvider est déjà '
    'true, FEAT-056 §2).',
  );
  return showDialog<void>(
    context: context,
    builder: (context) => _ScenarioLimitReachedDialog(plan: plan),
  );
}

/// Palier immédiatement supérieur à [level] parmi les paliers payants
/// (`pro` → `max` → `ultra`) — `null` si [level] est déjà le plus haut
/// (ne devrait pas arriver ici, cf. l'assert d'Ultra dans
/// [showScenarioLimitReachedModal]).
PlanLevel? _nextLevel(PlanLevel level) {
  final higher = PlanLevel.values.where((l) => l.rank > level.rank).toList()
    ..sort((a, b) => a.rank.compareTo(b.rank));
  return higher.isEmpty ? null : higher.first;
}

class _ScenarioLimitReachedDialog extends StatelessWidget {
  const _ScenarioLimitReachedDialog({required this.plan});

  final PlanEntitlement plan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tier = plan.tier;
    final isAnonymous = tier == SubscriptionTier.anonymous;
    final isPaid = tier == SubscriptionTier.paid;
    final nextLevel = isPaid ? _nextLevel(plan.level!) : null;
    final showUpgradeCta = !isAnonymous && !isStoreApp;
    // Sans aucun CTA (app store, hors anonyme), « Plus tard » n'a plus d'objet.
    final hasCta = isAnonymous || showUpgradeCta;

    return AlertDialog(
      key: const Key('scenario_limit_reached_modal'),
      title: Text(_titleFor(l10n, isAnonymous: isAnonymous, isPaid: isPaid)),
      content: Text(
        isPaid && nextLevel != null
            ? l10n.simulatorLimitReachedContentPaid(
                plan.level!.label(context),
                nextLevel.label(context),
              )
            : isAnonymous
            ? l10n.simulatorLimitReachedContentAnonymous
            : l10n.simulatorLimitReachedContentFree,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            hasCta ? l10n.simulatorLimitReachedLaterButton : l10n.commonClose,
          ),
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
        else if (showUpgradeCta)
          FilledButton(
            key: const Key('scenario_limit_upgrade_cta'),
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/pro');
            },
            child: Text(
              isPaid && nextLevel != null
                  ? l10n.proUpgradeToLevel(nextLevel.label(context))
                  : l10n.proUpgradeButton,
            ),
          ),
      ],
    );
  }

  String _titleFor(
    AppLocalizations l10n, {
    required bool isAnonymous,
    required bool isPaid,
  }) {
    if (isAnonymous) return l10n.simulatorLimitReachedTitleAnonymous;
    if (isPaid) return l10n.simulatorLimitReachedTitlePaid;
    return l10n.simulatorLimitReachedTitleFree;
  }
}
