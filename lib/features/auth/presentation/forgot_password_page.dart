import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../application/forgot_password_controller.dart';
import 'widgets/forgot_password_form.dart';
import 'widgets/password_reset_sent_view.dart';

/// Page de demande de réinitialisation de mot de passe.
class ForgotPasswordPage extends ConsumerWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(forgotPasswordControllerProvider);
    final showSent = pageState.maybeWhen(
      emailSent: () => true,
      orElse: () => false,
    );
    final l10n = context.l10n;

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
                    l10n.authForgotPasswordTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (!showSent)
                    Text(
                      l10n.authForgotPasswordInstructions,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 40),
                  if (showSent)
                    const PasswordResetSentView()
                  else
                    const ForgotPasswordForm(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
