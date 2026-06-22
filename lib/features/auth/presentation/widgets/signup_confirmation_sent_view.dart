import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Écran affiché après un signup réussi : demande de confirmer l'email.
class SignupConfirmationSentView extends StatelessWidget {
  const SignupConfirmationSentView({super.key});

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
          'Vérifiez votre boîte mail',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Un email de confirmation vous a été envoyé. '
          'Cliquez sur le lien dans cet email pour activer votre compte '
          'puis connectez-vous.',
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
