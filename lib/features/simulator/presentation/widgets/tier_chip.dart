import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/plan_entitlement.dart';
import '../../../auth/domain/plan_level.dart';
import '../../../auth/domain/subscription_tier.dart';
import '../../application/scenario_limit_controller.dart';

/// Chip persistant en haut de `/simulator` signalant le tier courant et la
/// consommation de quota.
///
/// - Anonyme : « MODE DÉMO · 1 SCÉNARIO »
/// - Free : « COMPTE GRATUIT · X/3 SCÉNARIOS » (compteur live)
/// - Paid : « PLAN PRO · ILLIMITÉ »
///
/// Style Baillan : EB Garamond italique, petites capitales trackées — cohérent
/// avec le reste de la marque (cf. `login_page.dart`).
class TierChip extends ConsumerWidget {
  const TierChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planEntitlementProvider);
    final count = ref.watch(scenarioCountProvider).valueOrNull;

    final label = _labelFor(context, plan, count);

    // Dark mode fix : les couleurs olive hardcodées disparaissent sur
    // fond ink. On pioche olive vs oliveSoft selon la brightness du thème
    // ambiant pour rester lisible dans les deux modes.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.oliveSoft : AppTheme.olive;
    final bgColor = isDark
        ? AppTheme.oliveSoft.withValues(alpha: 0.14)
        : AppTheme.oliveSoft.withValues(alpha: 0.18);
    final borderColor = isDark
        ? AppTheme.oliveSoft.withValues(alpha: 0.55)
        : AppTheme.olive.withValues(alpha: 0.35);

    return Container(
      key: const Key('tier_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'EB Garamond',
          fontStyle: FontStyle.italic,
          fontSize: 12.5,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  // Un seul libellé « PLAN PRO » pour tout compte payant (Pro/Max/Ultra) —
  // la différenciation visuelle par palier est un lot séparé (FEAT-056 PR-6).
  // `atLeast` reste le seul comparateur autorisé, jamais `tier ==
  // SubscriptionTier.paid` ni le rang d'un enum Dart.
  String _labelFor(BuildContext context, PlanEntitlement plan, int? count) {
    final l10n = context.l10n;
    if (plan.atLeast(PlanLevel.pro)) return l10n.simulatorTierChipPaid;
    if (plan.tier == SubscriptionTier.free) {
      return l10n.simulatorTierChipFree(count ?? 0);
    }
    return l10n.simulatorTierChipAnonymous;
  }
}
