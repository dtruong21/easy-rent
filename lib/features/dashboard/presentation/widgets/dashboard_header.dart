import 'package:flutter/material.dart';

/// Header du dashboard avec salutation et date du jour.
///
/// Affiche "Bonjour, [firstName]" + date du jour formatée en français.
/// [firstName] est nullable (profil incomplet lors du 1er login).
///
/// On utilise un formatage manuel pour éviter la dépendance sur
/// les données de locale intl (non chargées automatiquement dans les tests).
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key, this.firstName});

  /// Prénom du bailleur (peut être null si profil incomplet).
  final String? firstName;

  static const _months = [
    '', // index 0 inutilisé
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  static const _days = [
    '', // index 0 inutilisé
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dayName = _days[now.weekday]; // weekday 1=lundi..7=dimanche
    final dateLabel = '$dayName ${now.day} ${_months[now.month]} ${now.year}';
    final greeting = firstName != null && firstName!.isNotEmpty
        ? 'Bonjour, $firstName'
        : 'Bonjour';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
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
