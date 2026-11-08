import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../auth/application/delete_account_controller.dart';
import '../../auth/domain/delete_account_error.dart';
import '../../auth/domain/delete_account_reauth_method.dart';
import '../../auth/domain/delete_account_state.dart';
import '../../auth/presentation/delete_account_error_l10n.dart';
import '../../auth/presentation/widgets/password_field.dart';
import 'widgets/delete_account_subscription_notice.dart';
import 'widgets/delete_account_warning.dart';

/// Page `/profile/delete-account` — suppression de compte in-app
/// (FEAT-045, RGPD art. 17 ; exigence Google Play « Account deletion » et
/// App Store 5.1.1(v)).
///
/// Confirmation forte en trois temps : (1) avertissement des conséquences
/// + mention de rétention légale des quittances, (2) case de consentement
/// explicite + réauthentification adaptée au compte (mot de passe, ou flux
/// OAuth Google/Apple relancé), (3) dialog de confirmation finale. La
/// purge elle-même est faite côté serveur (callable `deleteAccount`).
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _passwordController = TextEditingController();
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_rebuild);
    _passwordController.dispose();
    super.dispose();
  }

  bool _canSubmit(DeleteAccountReauthMethod method, bool isWorking) {
    if (isWorking || !_acknowledged) return false;
    if (method == DeleteAccountReauthMethod.password) {
      return _passwordController.text.isNotEmpty;
    }
    return true;
  }

  Future<void> _confirmThenSubmit(DeleteAccountReauthMethod method) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteAccountConfirmDialogTitle),
        content: Text(l10n.deleteAccountConfirmDialogBody),
        actions: [
          TextButton(
            key: const Key('btn_delete_account_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('btn_delete_account_confirm'),
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

    final controller = ref.read(deleteAccountControllerProvider.notifier);
    switch (method) {
      case DeleteAccountReauthMethod.password:
        await controller.submitWithPassword(_passwordController.text);
      case DeleteAccountReauthMethod.google:
        await controller.submitWithGoogle();
      case DeleteAccountReauthMethod.apple:
        await controller.submitWithApple();
      case DeleteAccountReauthMethod.none:
        await controller.submitWithoutReauth();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final method = ref.watch(deleteAccountReauthMethodProvider);
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
          // ScaffoldMessenger racine (MaterialApp) : le SnackBar survit à la
          // navigation. AUCUN context.go ici : au moment où ce listener
          // tourne, le flip de session (stream userChanges → signOut) n'est
          // pas encore livré — une navigation explicite serait re-routée par
          // la garde avec l'état PÉRIMÉ (fullyAuthenticated → /dashboard).
          // On laisse la garde rediriger d'elle-même vers /login dès que
          // sessionStateProvider bascule sur unauthenticated.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.deleteAccountSuccessSnackbar)),
          );
        },
        orElse: () {},
      );
    });

    return Scaffold(
      appBar: AppAppBar(
        title: context.l10n.deleteAccountPageTitle,
        fallbackRoute: '/profile',
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DeleteAccountWarning(),
                const DeleteAccountSubscriptionNotice(),
                const SizedBox(height: 24),
                _ReauthSection(
                  method: method,
                  passwordController: _passwordController,
                  enabled: !isWorking,
                ),
                CheckboxListTile(
                  key: const Key('check_delete_account_ack'),
                  value: _acknowledged,
                  onChanged: isWorking
                      ? null
                      : (v) => setState(() => _acknowledged = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    context.l10n.deleteAccountAcknowledgeLabel,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage,
                    key: const Key('txt_delete_account_error'),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('btn_delete_account_submit'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: _canSubmit(method, isWorking)
                      ? () => _confirmThenSubmit(method)
                      : null,
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
                  label: Text(context.l10n.deleteAccountSubmitButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Étape de réauthentification, adaptée au type de compte : champ mot de
/// passe (comptes email) ou annonce du flux OAuth qui sera relancé à la
/// confirmation (Google/Apple — la fenêtre s'ouvre après le dialog).
class _ReauthSection extends StatelessWidget {
  const _ReauthSection({
    required this.method,
    required this.passwordController,
    required this.enabled,
  });

  final DeleteAccountReauthMethod method;
  final TextEditingController passwordController;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    switch (method) {
      case DeleteAccountReauthMethod.password:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.deleteAccountPasswordPrompt,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              PasswordField(
                key: const Key('field_delete_account_password'),
                controller: passwordController,
                labelText: l10n.profilePasswordCurrentLabel,
                autofillHints: const [AutofillHints.password],
                enabled: enabled,
              ),
            ],
          ),
        );
      case DeleteAccountReauthMethod.google:
      case DeleteAccountReauthMethod.apple:
        // Nom de provider (proper noun) — non traduit, injecté dans le libellé.
        final providerLabel = method == DeleteAccountReauthMethod.google
            ? 'Google'
            : 'Apple';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.deleteAccountOAuthReauthNotice(providerLabel),
            key: const Key('txt_delete_account_reauth_oauth'),
            style: theme.textTheme.bodyMedium,
          ),
        );
      case DeleteAccountReauthMethod.none:
        return const SizedBox.shrink();
    }
  }
}
