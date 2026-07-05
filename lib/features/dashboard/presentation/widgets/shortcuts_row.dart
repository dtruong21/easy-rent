import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/theme/app_spacing.dart';

/// Point d'entrée compact vers le simulateur d'investissement.
///
/// FEAT-026 : les raccourcis Biens/Locataires/Baux ont disparu — ce sont
/// désormais des destinations persistantes du shell adaptatif
/// (docs/UX_NAVIGATION.md §7). Seul le simulateur reste ici : il vit HORS du
/// shell (accessible aussi aux anonymes, §3.4 du doc), c'est le seul
/// « ailleurs » utile depuis l'onglet Accueil.
class ShortcutsRow extends StatelessWidget {
  const ShortcutsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing =
        Theme.of(context).extension<AppSpacing>() ?? const AppSpacing();
    return Wrap(
      spacing: spacing.md,
      runSpacing: 8,
      children: const [
        _ShortcutCard(
          key: Key('shortcut_simulator'),
          icon: Icons.calculate_outlined,
          label: 'Simuler un investissement',
          route: '/simulator',
        ),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    super.key,
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // push() (pas go()) : le simulateur est empilé PAR-DESSUS le shell,
        // le back natif dépile directement vers l'Accueil (docs/
        // UX_NAVIGATION.md §3.4).
        onTap: () => context.push(route),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.lg,
            vertical: spacing.md,
          ),
          // mainAxisSize.min + un Text non contraint provoquait un overflow
          // sur petits viewports mobiles (<400px) : le libellé complet
          // ("Simuler un investissement") ne rentrait pas dans la largeur
          // restante une fois les paddings de la ListView + de la Card
          // déduits. Flexible laisse le texte s'enrouler sur 2 lignes plutôt
          // que déborder, sans changer le rendu desktop (où il tient sur 1
          // ligne).
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Flexible(child: Text(label, style: theme.textTheme.labelLarge)),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
