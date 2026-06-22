import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Écran affiché après l'envoi du lien de réinitialisation.
class PasswordResetSentView extends StatelessWidget {
  const PasswordResetSentView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Lien envoyé',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Vérifiez votre boîte mail et cliquez sur le lien de '
          'réinitialisation. Le lien expire après 1 heure.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Retour à la connexion'),
        ),
      ],
    );
  }
}
