import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../application/auth_session_provider.dart';
import '../data/auth_repository.dart';
import 'widgets/reset_password_form.dart';

/// Page de réinitialisation du mot de passe.
///
/// Accessible via le lien envoyé par email (redirectTo=/reset-password).
/// Supabase établit une session temporaire de type [AuthChangeEvent.passwordRecovery]
/// avant que l'utilisateur ne soumette le nouveau mot de passe.
///
/// Si aucune session recovery n'est active (lien expiré, déjà utilisé ou accès
/// direct sans lien), on affiche un message d'erreur avec lien vers
/// /forgot-password plutôt que le formulaire.
class ResetPasswordPage extends ConsumerWidget {
  const ResetPasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateChangesProvider);

    // On détecte l'event passwordRecovery dans le stream auth pour confirmer
    // que l'utilisateur arrive bien via le lien de réinitialisation.
    // En cas de chargement initial, on se rabat sur la session en cache.
    final hasRecoverySession = authAsync.when(
      data: (authState) =>
          authState.event == AuthChangeEvent.passwordRecovery ||
          authState.session != null,
      loading: () {
        // En chargement initial, on se rabat sur la session en cache.
        return ref.read(authRepositoryProvider).currentSession != null;
      },
      error: (e, st) => false,
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nouveau mot de passe',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  if (hasRecoverySession)
                    const ResetPasswordForm()
                  else
                    _InvalidLinkView(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InvalidLinkView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.link_off_outlined, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 24),
        Text(
          'Lien invalide ou expiré',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Ce lien de réinitialisation est invalide ou a expiré. '
          'Demandez-en un nouveau.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => context.go('/forgot-password'),
          child: const Text('Demander un nouveau lien'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Retour à la connexion'),
        ),
      ],
    );
  }
}
