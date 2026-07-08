import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';

/// Modal bloquante affichée à J-1 (< 24h avant expiration de la session
/// anonyme). Contrairement au bandeau [AnonDemoBanner] (toujours visible,
/// non-bloquant), cette modal exige une action explicite de l'utilisateur.
Future<void> showAnonExpiryWarningDialog(BuildContext context) {
  final l10n = context.l10n;
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
      title: Text(l10n.authAnonExpiryDialogTitle),
      content: Text(l10n.authAnonExpiryDialogContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.authAnonExpiryDialogLaterButton),
        ),
        FilledButton(
          key: const Key('anon_expiry_warning_signup_cta'),
          onPressed: () {
            Navigator.of(context).pop();
            context.go('/signup');
          },
          child: Text(l10n.authCreateAccountLink),
        ),
      ],
    ),
  );
}
