import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/password_validator.dart';
import '../../../auth/application/change_password_controller.dart';
import '../../../auth/domain/change_password_state.dart';
import '../../../auth/presentation/widgets/password_field.dart';

/// Formulaire inline de changement de mot de passe (mot de passe actuel,
/// nouveau, confirmation).
///
/// Monté uniquement par [ProfileSecuritySection] quand
/// `hasPasswordProvider` vaut `true`. Réauthentifie via
/// [ChangePasswordController.submit] puis met à jour le mot de passe — la
/// session courante n'est jamais interrompue.
class ProfileChangePasswordForm extends ConsumerStatefulWidget {
  const ProfileChangePasswordForm({super.key});

  @override
  ConsumerState<ProfileChangePasswordForm> createState() =>
      _ProfileChangePasswordFormState();
}

class _ProfileChangePasswordFormState
    extends ConsumerState<ProfileChangePasswordForm> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentController.addListener(_rebuild);
    _newController.addListener(_rebuild);
    _confirmController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _currentController.removeListener(_rebuild);
    _newController.removeListener(_rebuild);
    _confirmController.removeListener(_rebuild);
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _currentController.text.isNotEmpty &&
      PasswordValidator.validate(_newController.text) == null &&
      _newController.text == _confirmController.text;

  Future<void> _submit() async {
    await ref
        .read(changePasswordControllerProvider.notifier)
        .submit(
          currentPassword: _currentController.text,
          newPassword: _newController.text,
          confirmPassword: _confirmController.text,
        );
  }

  void _clearFields() {
    _currentController.clear();
    _newController.clear();
    _confirmController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(changePasswordControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );
    final theme = Theme.of(context);

    ref.listen<ChangePasswordState>(changePasswordControllerProvider, (
      _,
      next,
    ) {
      next.maybeWhen(
        success: () {
          _clearFields();
          ref.read(changePasswordControllerProvider.notifier).reset();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Mot de passe mis à jour'),
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          );
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
            key: const Key('field_current_password'),
            controller: _currentController,
            labelText: 'Mot de passe actuel',
            autofillHints: const [AutofillHints.password],
            enabled: !isSubmitting,
          ),
          const SizedBox(height: 16),
          PasswordField(
            key: const Key('field_new_password'),
            controller: _newController,
            labelText: 'Nouveau mot de passe',
            autofillHints: const [AutofillHints.newPassword],
            enabled: !isSubmitting,
          ),
          const SizedBox(height: 4),
          Text(
            '8 caractères min, 1 lettre, 1 chiffre',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          PasswordField(
            key: const Key('field_confirm_password'),
            controller: _confirmController,
            labelText: 'Confirmer le nouveau mot de passe',
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
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('btn_change_password'),
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
                : const Text('Changer mon mot de passe'),
          ),
        ],
      ),
    );
  }
}
