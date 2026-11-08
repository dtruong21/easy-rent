import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Dialog affiché quand la Cloud Function retourne 422 `profile_incomplete`.
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

  /// Champs manquants retournés par la Cloud Function.
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return AlertDialog(
      key: const Key('dialog_profile_incomplete'),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Text(l10n.receiptsProfileIncompleteTitle),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.receiptsProfileIncompleteMessage),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.receiptsProfileIncompleteFieldsHeader,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 4),
            for (final field in missing)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text(
                  '• ${_fieldLabel(context, field)}',
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
          child: Text(l10n.receiptsProfileIncompleteLaterButton),
        ),
        FilledButton(
          key: const Key('btn_profile_incomplete_go'),
          onPressed: () {
            Navigator.of(context).pop();
            context.push('/profile');
          },
          child: Text(l10n.receiptsProfileIncompleteGoButton),
        ),
      ],
    );
  }

  /// Libellé localisé pour un nom de champ technique retourné par l'Edge
  /// Function (FEAT-043).
  String _fieldLabel(BuildContext context, String field) {
    final l10n = context.l10n;
    return switch (field) {
      'full_name' => l10n.receiptsProfileIncompleteFieldFullName,
      'address' => l10n.receiptsProfileIncompleteFieldAddress,
      'phone' => l10n.receiptsProfileIncompleteFieldPhone,
      _ => field,
    };
  }
}
