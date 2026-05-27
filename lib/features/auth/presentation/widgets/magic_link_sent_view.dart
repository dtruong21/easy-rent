import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth_controller.dart';

/// Écran affiché après l'envoi du magic link.
///
/// Couvre deux cas :
/// 1. Flux nominal : "Vérifiez votre boîte mail…"
/// 2. Magic link ouvert dans un autre navigateur (PKCE) : message clair
///    + bouton "Renvoyer un lien".
class MagicLinkSentView extends ConsumerWidget {
  const MagicLinkSentView({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          'Un lien de connexion vous a été envoyé à :',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          email,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // Cas "lien ouvert dans un autre navigateur"
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                'Vous avez ouvert le lien depuis un autre navigateur ?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Pour des raisons de sécurité (PKCE), le lien doit être '
                'ouvert dans le même navigateur que celui utilisé pour '
                'la demande de connexion.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => ref.read(authControllerProvider.notifier).reset(),
          child: const Text('Renvoyer un lien'),
        ),
      ],
    );
  }
}
