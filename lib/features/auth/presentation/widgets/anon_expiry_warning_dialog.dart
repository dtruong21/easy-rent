import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Modal bloquante affichée à J-1 (< 24h avant expiration de la session
/// anonyme). Contrairement au bandeau [AnonDemoBanner] (toujours visible,
/// non-bloquant), cette modal exige une action explicite de l'utilisateur.
Future<void> showAnonExpiryWarningDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    // J-1 est un moment de bascule critique — le plan exige une modal
    // BLOQUANTE. barrierDismissible=false force l'utilisateur à choisir
    // explicitement "Plus tard" ou "Créer un compte" plutôt que de la
    // faire disparaître par un tap accidentel hors-modale.
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const Key('anon_expiry_warning_dialog'),
      // Ton "registre notarial" plutôt que compte à rebours startup —
      // pas de "Plus que 24h" agressif à la MailChimp.
      title: const Text('Session démo — dernier jour'),
      content: const Text(
        'Votre session démo arrive à échéance dans moins de 24 heures. '
        'Passé ce délai, vos scénarios sauvegardés sont supprimés. Créez '
        'un compte gratuit pour les conserver.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          key: const Key('anon_expiry_warning_signup_cta'),
          onPressed: () {
            Navigator.of(context).pop();
            context.go('/signup');
          },
          child: const Text('Créer un compte'),
        ),
      ],
    ),
  );
}
