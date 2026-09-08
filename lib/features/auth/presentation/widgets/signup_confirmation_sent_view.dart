import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/ui/theme/app_icon_size.dart';

/// Écran affiché après un signup réussi : demande de confirmer l'email.
class SignupConfirmationSentView extends StatelessWidget {
  const SignupConfirmationSentView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: AppIconSize.hero,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          l10n.authCheckYourEmailTitle,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.authSignupConfirmationMessage,
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: Text(l10n.authBackToLoginButton),
        ),
      ],
    );
  }
}
