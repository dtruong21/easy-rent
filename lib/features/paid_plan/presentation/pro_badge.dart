import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/cards/status_pill_tone.dart';
import '../../../core/ui/theme/app_colors.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/plan_level.dart';
import 'widgets/plan_level_label.dart';

/// Badge de palier (FEAT-056 PR-6) — affiche le palier réel de l'abonné
/// (Pro/Max/Ultra) plutôt qu'un simple état payant/gratuit, avec une couleur
/// distincte par palier issue des design tokens ([AppColors], dark-mode
/// safe) — jamais de couleur littérale.
class ProBadge extends ConsumerWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(planEntitlementProvider).level;
    if (level == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors =
        theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark
            ? AppColors.dark
            : AppColors.light);
    final colorSet = colors.statusFor(_toneFor(level));

    return Container(
      key: Key('pro_badge_${level.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorSet.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        level.label(context).toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorSet.onSurface,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Tone visuel par palier — ordre croissant de « distinction » sans
  /// jugement de valeur (aucun tone n'est `danger`) : Pro reste neutre
  /// (palier d'entrée), Max en `info` (bleu), Ultra en `success` (le palier
  /// le plus complet).
  StatusPillTone _toneFor(PlanLevel level) => switch (level) {
    PlanLevel.pro => StatusPillTone.neutral,
    PlanLevel.max => StatusPillTone.info,
    PlanLevel.ultra => StatusPillTone.success,
  };
}
