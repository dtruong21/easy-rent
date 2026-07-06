import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Dialog d'avertissement affiché quand un bail actif existe déjà pour le
/// bien sélectionné.
///
/// L'utilisateur peut annuler ou confirmer la création malgré l'avertissement.
/// Cas d'usage : copropriété, erreur de saisie, transition entre locataires.
class ActiveLeaseWarningDialog extends StatelessWidget {
  const ActiveLeaseWarningDialog({super.key, required this.onConfirm});

  /// Callback appelé quand l'utilisateur choisit "Continuer" malgré
  /// l'avertissement.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.leasesActiveWarningDialogTitle),
      content: Text(l10n.leasesActiveWarningDialogContent),
      actions: [
        TextButton(
          key: const Key('btn_warning_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('btn_warning_confirm'),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          child: Text(l10n.leasesActiveWarningDialogConfirmButton),
        ),
      ],
    );
  }
}
