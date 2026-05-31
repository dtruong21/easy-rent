import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Dialog affiché quand l'Edge Function retourne 422 `profile_incomplete`.
///
/// Informe le bailleur que son profil doit être complété avant de pouvoir
/// générer une quittance (loi du 6 juillet 1989 art. 21 — nom et adresse
/// du bailleur sont des mentions obligatoires).
///
/// Actions :
/// - "Plus tard" : ferme le dialog sans naviguer.
/// - "Compléter mon profil" : navigue vers `/profile`.
class ProfileIncompleteDialog extends StatelessWidget {
  const ProfileIncompleteDialog({super.key, this.missing = const []});

  /// Champs manquants retournés par l'Edge Function.
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('dialog_profile_incomplete'),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          const Text('Profil incomplet'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pour générer une quittance, vous devez d\'abord compléter '
            'votre profil bailleur (nom et adresse sont obligatoires '
            'conformément à la loi du 6 juillet 1989).',
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Champs manquants :',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 4),
            for (final field in missing)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text(
                  '• ${_fieldLabel(field)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('btn_profile_incomplete_later'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          key: const Key('btn_profile_incomplete_go'),
          onPressed: () {
            Navigator.of(context).pop();
            context.push('/profile');
          },
          child: const Text('Compléter mon profil'),
        ),
      ],
    );
  }

  /// Libellé français pour un nom de champ technique.
  String _fieldLabel(String field) => switch (field) {
    'full_name' => 'Nom complet',
    'address' => 'Adresse postale',
    'phone' => 'Téléphone',
    _ => field,
  };
}
