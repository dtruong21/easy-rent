import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Blocs d'information du flux de suppression de compte (FEAT-045) :
/// conséquences irréversibles + mention de rétention légale des quittances.
///
/// La mention quittances est une exigence de conformité stores : la
/// rétention (loi n° 89-462 du 6 juillet 1989, 5 ans) n'est admise par les
/// politiques Google Play / App Store que si elle est ANNONCÉE dans le
/// flux de suppression — texte aligné sur la politique de confidentialité
/// (§5 « Durée de conservation »).
///
/// i18n (FEAT-043) : le chrome (titres, intro, liste, rappel) est traduit ;
/// le corps de la notice de rétention reste 100 % FR car il porte la citation
/// légale contraignante (loi n° 89-462, art. 2224 Code civil) — même règle que
/// les documents légaux (CGU, confidentialité), cf. `l10n_convention.dart` §7.
class DeleteAccountWarning extends StatelessWidget {
  const DeleteAccountWarning({super.key});

  /// Corps de la notice de rétention — contenu légal, non traduit (voir doc de
  /// classe). Le test widget vérifie la présence de la citation et de « 5 ans »
  /// indépendamment de la locale active.
  static const _receiptsRetentionBodyFr =
      'Seules vos quittances de loyer émises sont conservées '
      'pendant 5 ans à titre de preuve (loi n° 89-462 du '
      '6 juillet 1989 ; art. 2224 du Code civil), sous forme '
      'archivée et inaccessible, puis supprimées. Tout le reste '
      'est effacé immédiatement, conformément à notre politique '
      'de confidentialité.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;

    final deletedItems = [
      l10n.deleteAccountWarningItemProperties,
      l10n.deleteAccountWarningItemTenants,
      l10n.deleteAccountWarningItemDocuments,
      l10n.deleteAccountWarningItemSimulations,
      l10n.deleteAccountWarningItemAccount,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.35),
            border: Border.all(color: colorScheme.error),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.deleteAccountWarningTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.deleteAccountWarningIntro,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              for (final item in deletedItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('•  $item', style: theme.textTheme.bodyMedium),
                ),
              const SizedBox(height: 8),
              Text(
                l10n.deleteAccountWarningDownloadReminder,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          key: const Key('box_receipts_retention_notice'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.deleteAccountRetentionTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                _receiptsRetentionBodyFr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
