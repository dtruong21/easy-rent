import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/landlord_tier_repository.dart';
import '../../../auth/domain/subscription_tier.dart';
import '../../application/scenario_limit_controller.dart';

/// Chip persistant en haut de `/simulator` signalant le tier courant et la
/// consommation de quota.
///
/// - Anonyme : « MODE DÉMO · 1 SCÉNARIO »
/// - Free : « COMPTE GRATUIT · X/3 SCÉNARIOS » (compteur live)
/// - Paid : « PLAN PRO · ILLIMITÉ »
///
/// Style Baillan : Cochin italique, petites capitales trackées — cohérent
/// avec le reste de la marque (cf. `login_page.dart`).
class TierChip extends ConsumerWidget {
  const TierChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTier = ref.watch(landlordTierProvider);
    final tier = asyncTier.valueOrNull?.tier ?? SubscriptionTier.anonymous;
    final count = ref.watch(scenarioCountProvider).valueOrNull;

    final label = _labelFor(tier, count);

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
          fontFamily: 'Cochin',
          fontStyle: FontStyle.italic,
          fontSize: 12.5,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  String _labelFor(SubscriptionTier tier, int? count) {
    switch (tier) {
      case SubscriptionTier.anonymous:
        return 'MODE DÉMO · 1 SCÉNARIO';
      case SubscriptionTier.free:
        final c = count ?? 0;
        return 'COMPTE GRATUIT · $c/3 SCÉNARIOS';
      case SubscriptionTier.paid:
        return 'PLAN PRO · ILLIMITÉ';
    }
  }
}
