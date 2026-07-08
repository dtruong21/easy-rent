import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../auth/application/auth_session_provider.dart';
import 'widgets/profile_change_password_form.dart';

/// Page `/profile/password` — changement de mot de passe in-app (FEAT-025).
///
/// **Garde-fou** : si l'utilisateur n'a pas de mot de passe Firebase Auth
/// ([hasPasswordProvider] == `false` — compte Google, Apple ou session
/// anonyme), le formulaire n'est pas monté. Ce cas ne devrait pas se
/// présenter en usage normal (le hub /profile masque la tuile
/// correspondante) mais reste accessible par URL directe.
class ChangePasswordPage extends ConsumerWidget {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPassword = ref.watch(hasPasswordProvider);

    return Scaffold(
      appBar: AppAppBar(
        title: context.l10n.profilePasswordTitle,
        fallbackRoute: '/profile',
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: hasPassword
                ? const ProfileChangePasswordForm()
                : _NoPasswordNotice(),
          ),
        ),
      ),
    );
  }
}

/// Message affiché quand le compte connecté n'a pas de mot de passe Firebase
/// Auth (comptes Google/Apple, accès direct par URL).
class _NoPasswordNotice extends StatelessWidget {
  const _NoPasswordNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      key: const Key('txt_no_password_notice'),
      context.l10n.profilePasswordManagedByProviderNotice,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      textAlign: TextAlign.center,
    );
  }
}
