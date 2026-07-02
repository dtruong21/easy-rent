import 'package:flutter/material.dart';

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
  return showDialog<QuitDemoChoice>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('quit_demo_dialog'),
      title: const Text('Quitter le mode démo ?'),
      content: const Text(
        'Votre session démo sera clôturée et son scénario définitivement '
        'perdu. Créez un compte gratuit pour le conserver.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          key: const Key('quit_demo_dialog_signup'),
          onPressed: () => Navigator.of(context).pop(QuitDemoChoice.signup),
          child: const Text('Créer un compte'),
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
          child: const Text('Quitter'),
        ),
      ],
    ),
  );
}
