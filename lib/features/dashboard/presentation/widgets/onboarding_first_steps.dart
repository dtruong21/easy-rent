import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.rocket_launch_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('Bienvenue ! Premiers pas', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Suivez ces 3 étapes pour démarrer.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _StepTile(
              stepNumber: 1,
              label: 'Ajouter un bien',
              icon: Icons.home_outlined,
              route: '/properties/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 2,
              label: 'Ajouter un locataire',
              icon: Icons.person_outline,
              route: '/tenants/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 3,
              label: 'Créer un bail',
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
      onTap: () => context.go(route),
    );
  }
}
