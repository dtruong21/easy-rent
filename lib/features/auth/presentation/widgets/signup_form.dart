import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/email_validator.dart';
import '../../../../core/utils/password_validator.dart';
import '../../application/signup_controller.dart';
import 'password_field.dart';

/// Formulaire de création de compte.
class SignupForm extends ConsumerStatefulWidget {
  const SignupForm({super.key});

  @override
  ConsumerState<SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends ConsumerState<SignupForm> {
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _rgpdConsent = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_rebuild);
    _confirmPasswordController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_rebuild);
    _confirmPasswordController.removeListener(_rebuild);
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _fullNameController.text.trim().isNotEmpty &&
      EmailValidator.isValid(_emailController.text) &&
      PasswordValidator.validate(_passwordController.text) == null &&
      _passwordController.text == _confirmPasswordController.text &&
      _rgpdConsent;

  Future<void> _submit() async {
    await ref
        .read(signupControllerProvider.notifier)
        .signUp(
          fullName: _fullNameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          confirmPassword: _confirmPasswordController.text,
          rgpdConsent: _rgpdConsent,
        );
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(signupControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );
    final theme = Theme.of(context);

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _fullNameController,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            autocorrect: false,
            autofillHints: const [AutofillHints.name],
            enabled: !isSubmitting,
            decoration: const InputDecoration(
              labelText: 'Nom complet',
              hintText: 'Jean Dupont',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [
              AutofillHints.email,
              AutofillHints.newUsername,
            ],
            enabled: !isSubmitting,
            decoration: const InputDecoration(
              labelText: 'Adresse email',
              hintText: 'vous@exemple.fr',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _passwordController,
            labelText: 'Mot de passe',
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
            controller: _confirmPasswordController,
            labelText: 'Confirmer le mot de passe',
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
          _RgpdCheckbox(
            value: _rgpdConsent,
            enabled: !isSubmitting,
            onChanged: (v) => setState(() => _rgpdConsent = v ?? false),
          ),
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
                : const Text('Créer mon compte'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text("J'ai déjà un compte"),
          ),
        ],
      ),
    );
  }
}

class _RgpdCheckbox extends StatefulWidget {
  const _RgpdCheckbox({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  @override
  State<_RgpdCheckbox> createState() => _RgpdCheckboxState();
}

class _RgpdCheckboxState extends State<_RgpdCheckbox> {
  // Stocké en champ pour être disposé proprement et éviter les memory leaks.
  final _recognizer = TapGestureRecognizer();

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _recognizer.onTap = () => context.go('/privacy');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: widget.value,
          onChanged: widget.enabled ? widget.onChanged : null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  const TextSpan(text: "J'accepte la "),
                  TextSpan(
                    text: 'politique de confidentialité',
                    style: TextStyle(
                      color: colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: _recognizer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
