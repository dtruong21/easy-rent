import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_icon_size.dart';
import '../../../../core/ui/theme/app_spacing.dart';

/// Checklist d'onboarding "Premiers pas".
///
/// Affiché à la place des KPI cards quand le bailleur n'a
/// aucun bien, locataire ni bail ([DashboardSnapshot.isOnboarding] == `true`).
///
/// Les 3 steps sont cliquables et naviguent vers les pages de création.
class OnboardingFirstSteps extends StatelessWidget {
  const OnboardingFirstSteps({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.rocket_launch_outlined,
              size: AppIconSize.hero,
              color: theme.colorScheme.primary,
            ),
            SizedBox(height: spacing.md),
            Text(
              l10n.dashboardOnboardingTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.dashboardOnboardingSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: spacing.xl),
            _StepTile(
              stepNumber: 1,
              label: l10n.dashboardOnboardingStepAddPropertyLabel,
              icon: Icons.home_outlined,
              route: '/properties/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 2,
              label: l10n.dashboardOnboardingStepAddTenantLabel,
              icon: Icons.person_outline,
              route: '/tenants/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 3,
              label: l10n.dashboardOnboardingStepCreateLeaseLabel,
              icon: Icons.description_outlined,
              route: '/leases/new',
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.stepNumber,
    required this.label,
    required this.icon,
    required this.route,
  });

  final int stepNumber;
  final String label;
  final IconData icon;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          '$stepNumber',
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
      title: Text(label, style: theme.textTheme.bodyLarge),
      trailing: Icon(Icons.chevron_right, color: theme.colorScheme.primary),
      // push() (pas go()) : depuis l'onglet Accueil, on empile le formulaire
      // de création sans changer d'onglet — pop() ramène directement à
      // l'Accueil (F-1, docs/UX_NAVIGATION.md §5).
      onTap: () => context.push(route),
    );
  }
}
