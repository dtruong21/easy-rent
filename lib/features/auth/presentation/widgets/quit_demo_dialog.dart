import 'package:flutter/material.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Choix retourné par [showQuitDemoDialog].
enum QuitDemoChoice {
  /// L'utilisateur préfère convertir sa session en compte (conserve le
  /// scénario démo via le link anonyme → compte complet).
  signup,

  /// L'utilisateur confirme l'abandon : signOut de la session anonyme,
  /// le scénario démo devient définitivement inaccessible.
  quit,
}

/// Dialog de confirmation avant de quitter le mode démo (session anonyme).
///
/// Contrairement à [showAnonExpiryWarningDialog] (subie, à J-1), cette modal
/// est déclenchée par l'utilisateur — elle reste dismissible (tap hors modal
/// = annuler). La navigation et le signOut sont à la charge de l'appelant :
/// le dialog ne fait que recueillir le choix, retourne `null` si annulé.
Future<QuitDemoChoice?> showQuitDemoDialog(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<QuitDemoChoice>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('quit_demo_dialog'),
      title: Text(l10n.authQuitDemoDialogTitle),
      content: Text(l10n.authQuitDemoDialogContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          key: const Key('quit_demo_dialog_signup'),
          onPressed: () => Navigator.of(context).pop(QuitDemoChoice.signup),
          child: Text(l10n.authCreateAccountLink),
        ),
        FilledButton(
          key: const Key('quit_demo_dialog_confirm'),
          // Oxblood : action destructive (perte du scénario), même registre
          // que "quittance annulée" — pas le olive des actions nominales.
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(QuitDemoChoice.quit),
          child: Text(l10n.authQuitDemoDialogConfirmButton),
        ),
      ],
    ),
  );
}
