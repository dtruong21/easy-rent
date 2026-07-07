import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../application/delete_account_controller.dart';
import '../application/auth_session_provider.dart';
import '../domain/delete_account_state.dart';
import '../domain/session_state.dart';

/// Page publique `/delete-account` — demande de suppression de compte
/// Baillan (FEAT-045).
///
/// Exigence Google Play « Account deletion » (answer 13327111) : une URL
/// web, déclarée sur la fiche du store, permettant de demander la
/// suppression du compte SANS réinstaller l'application. Accessible sans
/// authentification (hors shell, comme `/privacy`).
///
/// La page s'adapte à la session courante :
/// - visiteur non connecté → étapes + bouton vers la connexion ;
/// - compte complet → bouton direct vers `/profile/delete-account` ;
/// - session anonyme (essai) → suppression immédiate de l'essai et de ses
///   données (aucun credential à re-présenter, dialog de confirmation).
class DeleteAccountRequestPage extends ConsumerWidget {
  const DeleteAccountRequestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessionState = ref.watch(sessionStateProvider);

    return Scaffold(
      appBar: AppAppBar(title: 'Suppression de compte', fallbackRoute: '/'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Supprimer votre compte Baillan',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'La suppression de votre compte Baillan est immédiate, '
                    'définitive et efface l\'ensemble de vos données : biens, '
                    'locataires, baux, paiements, documents, dépenses, '
                    'simulations, profil et compte de connexion (email, '
                    'Google ou Apple).\n\n'
                    'Seules vos quittances de loyer émises sont conservées '
                    '5 ans à titre de preuve (loi n° 89-462 du 6 juillet '
                    '1989), sous forme archivée et inaccessible, puis '
                    'supprimées — voir notre politique de confidentialité.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Text('Comment procéder', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '1. Connectez-vous à Baillan (application mobile ou web).\n'
                    '2. Ouvrez l\'onglet « Profil » puis « Supprimer mon '
                    'compte ».\n'
                    '3. Confirmez votre identité (mot de passe, Google ou '
                    'Apple) et validez.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  _SessionAwareAction(sessionState: sessionState),
                  const SizedBox(height: 24),
                  Text(
                    'Vous avez perdu l\'accès à votre compte ? Utilisez '
                    '« Mot de passe oublié » sur l\'écran de connexion pour '
                    'le récupérer, puis procédez à la suppression.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('btn_delete_request_privacy'),
                    onPressed: () => context.push('/privacy'),
                    child: const Text('Politique de confidentialité'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton d'action principal, dérivé de l'état de session (3 branches).
class _SessionAwareAction extends ConsumerWidget {
  const _SessionAwareAction({required this.sessionState});

  final SessionState sessionState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (sessionState) {
      case SessionState.unauthenticated:
        return FilledButton.icon(
          key: const Key('btn_delete_request_login'),
          onPressed: () => context.go('/login'),
          icon: const Icon(Icons.login),
          label: const Text('Se connecter pour supprimer mon compte'),
        );
      case SessionState.fullyAuthenticated:
        return FilledButton.icon(
          key: const Key('btn_delete_request_go_profile'),
          onPressed: () => context.go('/profile/delete-account'),
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Supprimer mon compte maintenant'),
        );
      case SessionState.anonymous:
        return const _AnonymousDeleteAction();
    }
  }
}

/// Session d'essai (anonyme) : suppression directe après confirmation —
/// il n'existe aucun credential à re-présenter (la callable `deleteAccount`
/// exempte les tokens anonymes de la garde de fraîcheur).
class _AnonymousDeleteAction extends ConsumerWidget {
  const _AnonymousDeleteAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(deleteAccountControllerProvider);
    final isWorking = state.maybeWhen(working: () => true, orElse: () => false);
    final errorMessage = state.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );

    ref.listen<DeleteAccountState>(deleteAccountControllerProvider, (_, next) {
      next.maybeWhen(
        success: () {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Votre essai et ses données ont été supprimés.'),
            ),
          );
          context.go('/');
        },
        orElse: () {},
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vous utilisez actuellement Baillan en essai sans compte : la '
          'suppression efface immédiatement cette session et ses données '
          '(simulations d\'investissement).',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('btn_delete_request_anonymous'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: isWorking ? null : () => _confirmThenDelete(context, ref),
          icon: isWorking
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onError,
                  ),
                )
              : const Icon(Icons.delete_forever_outlined),
          label: const Text('Supprimer mon essai et ses données'),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            errorMessage,
            key: const Key('txt_delete_request_error'),
            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmThenDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer votre essai ?'),
        content: const Text(
          'Vos simulations et cette session d\'essai seront supprimées '
          'immédiatement. Cette action ne peut pas être annulée.',
        ),
        actions: [
          TextButton(
            key: const Key('btn_delete_request_anon_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('btn_delete_request_anon_confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(deleteAccountControllerProvider.notifier)
        .submitWithoutReauth();
  }
}
