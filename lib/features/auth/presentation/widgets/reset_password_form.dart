import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/password_validator.dart';
import '../../application/reset_password_controller.dart';
import '../../domain/auth_error.dart';
import '../../domain/reset_password_state.dart';
import '../auth_error_l10n.dart';
import 'password_field.dart';

/// Formulaire de réinitialisation du mot de passe.
///
/// Ce widget est monté uniquement si le `oobCode` reçu en URL est valide
/// (le parent [ResetPasswordPage] a déjà appelé `verifyPasswordResetCode`).
class ResetPasswordForm extends ConsumerStatefulWidget {
  const ResetPasswordForm({super.key, required this.oobCode});

  final String oobCode;

  @override
  ConsumerState<ResetPasswordForm> createState() => _ResetPasswordFormState();
}

class _ResetPasswordFormState extends ConsumerState<ResetPasswordForm> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_rebuild);
    _confirmController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_rebuild);
    _confirmController.removeListener(_rebuild);
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      PasswordValidator.validate(_passwordController.text) == null &&
      _passwordController.text == _confirmController.text;

  Future<void> _submit() async {
    await ref
        .read(resetPasswordControllerProvider.notifier)
        .confirmReset(
          oobCode: widget.oobCode,
          newPassword: _passwordController.text,
          confirmPassword: _confirmController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(resetPasswordControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorCode = formState.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );
    final errorMessage = errorCode != null
        ? AuthError.fromCode(errorCode).message(context)
        : null;
    final theme = Theme.of(context);
    final l10n = context.l10n;

    ref.listen<ResetPasswordState>(resetPasswordControllerProvider, (_, next) {
      next.maybeWhen(
        success: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.authPasswordUpdatedSnackbar)),
          );
          context.go('/login');
        },
        orElse: () {},
      );
    });

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PasswordField(
            controller: _passwordController,
            labelText: l10n.authNewPasswordLabel,
            autofillHints: const [AutofillHints.newPassword],
            enabled: !isSubmitting,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.authPasswordRequirementsHelper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _confirmController,
            labelText: l10n.authConfirmPasswordLabel,
            autofillHints: const [AutofillHints.newPassword],
            enabled: !isSubmitting,
            onSubmitted: _canSubmit ? _submit : null,
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
                : Text(l10n.authResetPasswordButton),
          ),
        ],
      ),
    );
  }
}
