import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../application/delete_account_controller.dart';
import '../application/auth_session_provider.dart';
import '../domain/delete_account_error.dart';
import '../domain/delete_account_state.dart';
import '../domain/session_state.dart';
import 'delete_account_error_l10n.dart';

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

  /// Phrase de rétention légale des quittances — contenu légal, non traduit
  /// (citation loi n° 89-462), appendue au paragraphe d'introduction traduit.
  /// Même règle que la notice du flux in-app (cf. `DeleteAccountWarning`) et
  /// les documents légaux, `l10n_convention.dart` §7. Le test widget vérifie
  /// la présence de la citation indépendamment de la locale active.
  static const _receiptsRetentionSentenceFr =
      'Seules vos quittances de loyer émises sont conservées '
      '5 ans à titre de preuve (loi n° 89-462 du 6 juillet '
      '1989), sous forme archivée et inaccessible, puis '
      'supprimées — voir notre politique de confidentialité.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sessionState = ref.watch(sessionStateProvider);

    return Scaffold(
      appBar: AppAppBar(
        title: l10n.deleteAccountRequestPageTitle,
        fallbackRoute: '/',
      ),
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
                    l10n.deleteAccountRequestHeading,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${l10n.deleteAccountRequestIntro}\n\n'
                    '$_receiptsRetentionSentenceFr',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.deleteAccountRequestStepsTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.deleteAccountRequestSteps,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  _SessionAwareAction(sessionState: sessionState),
                  const SizedBox(height: 24),
                  Text(
                    l10n.deleteAccountRequestLostAccess,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('btn_delete_request_privacy'),
                    onPressed: () => context.push('/privacy'),
                    child: Text(l10n.authPrivacyPolicyLink),
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
    final l10n = context.l10n;
    switch (sessionState) {
      case SessionState.unauthenticated:
        return FilledButton.icon(
          key: const Key('btn_delete_request_login'),
          onPressed: () => context.go('/login'),
          icon: const Icon(Icons.login),
          label: Text(l10n.deleteAccountRequestLoginButton),
        );
      case SessionState.fullyAuthenticated:
        return FilledButton.icon(
          key: const Key('btn_delete_request_go_profile'),
          onPressed: () => context.go('/profile/delete-account'),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(l10n.deleteAccountRequestGoProfileButton),
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
    final l10n = context.l10n;
    final state = ref.watch(deleteAccountControllerProvider);
    final isWorking = state.maybeWhen(working: () => true, orElse: () => false);
    final errorMessage = state.maybeWhen(
      error: (code) => DeleteAccountError.fromCode(code).message(context),
      orElse: () => null,
    );

    ref.listen<DeleteAccountState>(deleteAccountControllerProvider, (_, next) {
      next.maybeWhen(
        success: () {
          if (!context.mounted) return;
          // Pas de navigation explicite : /delete-account est publique pour
          // tous les états de session — quand le flip anonymous →
          // unauthenticated arrive (stream), la page se re-rend simplement
          // avec le CTA « Se connecter ». Un context.go ici serait re-routé
          // par la garde avec l'état de session PÉRIMÉ (cf. même commentaire
          // dans DeleteAccountPage).
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.deleteAccountRequestAnonSuccessSnackbar,
              ),
            ),
          );
        },
        orElse: () {},
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.deleteAccountRequestAnonDescription,
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
          label: Text(l10n.deleteAccountRequestAnonButton),
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
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteAccountRequestAnonDialogTitle),
        content: Text(l10n.deleteAccountRequestAnonDialogBody),
        actions: [
          TextButton(
            key: const Key('btn_delete_request_anon_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('btn_delete_request_anon_confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.commonDelete),
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
