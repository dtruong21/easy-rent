import 'package:flutter/material.dart';

/// Blocs d'information du flux de suppression de compte (FEAT-045) :
/// conséquences irréversibles + mention de rétention légale des quittances.
///
/// La mention quittances est une exigence de conformité stores : la
/// rétention (loi n° 89-462 du 6 juillet 1989, 5 ans) n'est admise par les
/// politiques Google Play / App Store que si elle est ANNONCÉE dans le
/// flux de suppression — texte aligné sur la politique de confidentialité
/// (§5 « Durée de conservation »).
class DeleteAccountWarning extends StatelessWidget {
  const DeleteAccountWarning({super.key});

  static const _deletedItems = [
    'vos biens immobiliers et leurs dépenses',
    'vos locataires, baux et paiements',
    'vos documents (y compris ceux sous verrou légal : baux signés, '
        'attestations d\'assurance)',
    'vos simulations d\'investissement',
    'votre profil bailleur et votre compte de connexion',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                      'Cette action est immédiate et irréversible',
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
                'La suppression de votre compte Baillan efface '
                'définitivement :',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              for (final item in _deletedItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('•  $item', style: theme.textTheme.bodyMedium),
                ),
              const SizedBox(height: 8),
              Text(
                'Pensez à télécharger au préalable les documents que vous '
                'souhaitez conserver : aucune récupération ne sera possible.',
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
                'Conservation légale des quittances',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Seules vos quittances de loyer émises sont conservées '
                'pendant 5 ans à titre de preuve (loi n° 89-462 du '
                '6 juillet 1989 ; art. 2224 du Code civil), sous forme '
                'archivée et inaccessible, puis supprimées. Tout le reste '
                'est effacé immédiatement, conformément à notre politique '
                'de confidentialité.',
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
