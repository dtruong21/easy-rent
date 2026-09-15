import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_icon_size.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../application/onboarding_dismissed_provider.dart';
import '../../domain/onboarding_progress.dart';

/// Checklist d'onboarding « Premiers pas », progressive et à état.
///
/// Affichée à la place des KPI tant que le bailleur n'a pas généré sa 1re
/// quittance ([OnboardingProgress.isComplete] == false) et n'a pas « passé »
/// la checklist. Chaque étape est cochée dès que son signal de données est
/// présent. Les étapes 4-5 (paiement, quittance) sont lease-scoped : sans
/// bail ([firstLeaseId] == null), elles sont désactivées.
class OnboardingFirstSteps extends ConsumerWidget {
  const OnboardingFirstSteps({required this.progress, super.key});

  final OnboardingProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final l10n = context.l10n;
    final leaseId = progress.firstLeaseId;

    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rocket_launch_outlined,
                  size: AppIconSize.hero,
                  color: theme.colorScheme.primary,
                ),
                const Spacer(),
                Text(
                  l10n.dashboardOnboardingProgressLabel(
                    progress.completedCount,
                    5,
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
              done: progress.hasProperty,
              route: '/properties/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 2,
              label: l10n.dashboardOnboardingStepAddTenantLabel,
              icon: Icons.person_outline,
              done: progress.hasTenant,
              route: '/tenants/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 3,
              label: l10n.dashboardOnboardingStepCreateLeaseLabel,
              icon: Icons.description_outlined,
              done: progress.hasLease,
              route: '/leases/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 4,
              label: l10n.dashboardOnboardingStepRecordPaymentLabel,
              icon: Icons.payments_outlined,
              done: progress.hasPayment,
              // Lease-scoped : désactivé tant qu'aucun bail.
              route: leaseId == null ? null : '/leases/$leaseId/payments/new',
            ),
            const Divider(height: 1),
            _StepTile(
              stepNumber: 5,
              label: l10n.dashboardOnboardingStepGenerateReceiptLabel,
              icon: Icons.receipt_long_outlined,
              done: progress.hasReceipt,
              route: leaseId == null ? null : '/leases/$leaseId/receipts',
            ),
            SizedBox(height: spacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    ref.read(onboardingDismissedProvider.notifier).dismiss(),
                child: Text(l10n.dashboardOnboardingSkip),
              ),
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
    required this.done,
    required this.route,
  });

  final int stepNumber;
  final String label;
  final IconData icon;
  final bool done;

  /// `null` = étape désactivée (prérequis manquant, ex. pas de bail).
  final String? route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = route == null && !done;

    final leading = done
        ? CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary,
            child: Icon(
              Icons.check,
              size: 18,
              color: theme.colorScheme.onPrimary,
            ),
          )
        : CircleAvatar(
            radius: 16,
            backgroundColor: disabled
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primaryContainer,
            child: Text(
              '$stepNumber',
              style: TextStyle(
                color: disabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          );

    return ListTile(
      enabled: !disabled,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: leading,
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(
          decoration: done ? TextDecoration.lineThrough : null,
          color: done || disabled ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      trailing: done
          ? null
          : Icon(
              Icons.chevron_right,
              color: disabled
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
      // push() : empile le formulaire depuis l'onglet Accueil (docs/UX_NAVIGATION.md §5).
      onTap: route == null ? null : () => context.push(route!),
    );
  }
}
