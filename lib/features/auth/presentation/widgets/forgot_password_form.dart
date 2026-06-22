import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/email_validator.dart';
import '../../application/forgot_password_controller.dart';

/// Formulaire de demande de réinitialisation de mot de passe.
class ForgotPasswordForm extends ConsumerStatefulWidget {
  const ForgotPasswordForm({super.key});

  @override
  ConsumerState<ForgotPasswordForm> createState() => _ForgotPasswordFormState();
}

class _ForgotPasswordFormState extends ConsumerState<ForgotPasswordForm> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool get _canSubmit => EmailValidator.isValid(_emailController.text);

  Future<void> _submit() async {
    await ref
        .read(forgotPasswordControllerProvider.notifier)
        .sendResetEmail(_emailController.text);
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(forgotPasswordControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          enabled: !isSubmitting,
          decoration: const InputDecoration(
            labelText: 'Adresse email',
            hintText: 'vous@exemple.fr',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _canSubmit ? _submit() : null,
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            errorMessage,
            style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: (_canSubmit && !isSubmitting) ? _submit : null,
          child: isSubmitting
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : const Text('Envoyer le lien de réinitialisation'),
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
