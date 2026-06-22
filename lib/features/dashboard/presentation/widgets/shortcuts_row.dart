import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ui/theme/app_spacing.dart';

/// Raccourcis compacts vers les 3 sections principales.
///
/// Remplace les 3 ListTiles de l'ancien dashboard.
/// Layout : Wrap responsive (cards icône + label sur une ligne).
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
          key: Key('shortcut_properties'),
          icon: Icons.home_outlined,
          label: 'Mes biens',
          route: '/properties',
        ),
        _ShortcutCard(
          key: Key('shortcut_tenants'),
          icon: Icons.people_outline,
          label: 'Locataires',
          route: '/tenants',
        ),
        _ShortcutCard(
          key: Key('shortcut_leases'),
          icon: Icons.description_outlined,
          label: 'Baux',
          route: '/leases',
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
        onTap: () => context.go(route),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.lg,
            vertical: spacing.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.labelLarge),
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
