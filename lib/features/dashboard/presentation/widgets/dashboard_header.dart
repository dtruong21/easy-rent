import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_spacing.dart';
import '../../../paid_plan/presentation/pro_badge.dart';

/// Header du dashboard avec salutation et date du jour.
///
/// Affiche "Bonjour, [firstName]" + date du jour formatée dans la locale
/// active (jour de semaine + jour + mois + année, ex. « lundi 6 juillet
/// 2026 » / « Monday, July 6, 2026 »). [firstName] est nullable (profil
/// incomplet lors du 1er login).
///
/// FEAT-043 : le formatage de date délègue à `DateFormat.yMMMMEEEEd` de
/// `package:intl`, piloté par la locale résolue de l'app (les symboles de
/// date sont initialisés via les délégués `AppLocalizations`, cf.
/// `main.dart`) — remplace l'ancien tableau de mois/jours FR en dur.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key, this.firstName});

  /// Prénom du bailleur (peut être null si profil incomplet).
  final String? firstName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<AppSpacing>() ?? const AppSpacing();
    final localeName = Localizations.localeOf(context).toString();
    final dateLabel = DateFormat.yMMMMEEEEd(localeName).format(DateTime.now());
    final l10n = context.l10n;
    final greeting = firstName != null && firstName!.isNotEmpty
        ? l10n.dashboardGreetingWithName(firstName!)
        : l10n.dashboardGreeting;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  greeting,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const ProBadge(),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            dateLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
