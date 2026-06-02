import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/email_validator.dart';
import '../../application/auth_controller.dart';
import '../../domain/login_form_state.dart';

/// Formulaire de connexion par magic link.
///
/// Règles d'activation du bouton :
/// - Adresse email valide
/// - Case de consentement RGPD cochée
///
/// Lorsque le state est [LoginFormState.error], le message s'affiche
/// sous le champ email.
class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _emailController = TextEditingController();
  bool _rgpdConsent = false;
  bool _emailTouched = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool get _emailValid => EmailValidator.isValid(_emailController.text);
  bool get _canSubmit => _emailValid && _rgpdConsent;

  Future<void> _submit() async {
    setState(() => _emailTouched = true);
    await ref
        .read(authControllerProvider.notifier)
        .sendMagicLink(email: _emailController.text, rgpdConsent: _rgpdConsent);
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(authControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg) => msg,
      orElse: () => null,
    );
    final showInlineError =
        _emailTouched && !_emailValid && errorMessage == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Champ email
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          enabled: !isSubmitting,
          decoration: InputDecoration(
            labelText: 'Adresse email',
            hintText: 'vous@exemple.fr',
            errorText: showInlineError ? 'Adresse email invalide' : null,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _canSubmit ? _submit() : null,
        ),

        // Message d'erreur retourné par Supabase
        if (errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            errorMessage,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 13,
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Case RGPD
        _RgpdCheckbox(
          value: _rgpdConsent,
          enabled: !isSubmitting,
          onChanged: (v) => setState(() => _rgpdConsent = v ?? false),
        ),

        const SizedBox(height: 24),

        // Bouton de soumission
        FilledButton(
          onPressed: (_canSubmit && !isSubmitting) ? _submit : null,
          child: isSubmitting
              ? SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : const Text('Recevoir mon lien de connexion'),
        ),
      ],
    );
  }
}

/// Case à cocher RGPD avec lien cliquable vers [/privacy].
class _RgpdCheckbox extends StatelessWidget {
  const _RgpdCheckbox({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: value, onChanged: enabled ? onChanged : null),
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
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => context.go('/privacy'),
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
