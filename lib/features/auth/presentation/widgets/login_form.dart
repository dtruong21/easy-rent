import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/email_validator.dart';
import '../../application/login_controller.dart';
import 'password_field.dart';

/// Formulaire de connexion email + mot de passe.
class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Rebuild quand le mot de passe change pour activer/désactiver le bouton.
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() => setState(() {});

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      EmailValidator.isValid(_emailController.text) &&
      _passwordController.text.isNotEmpty;

  Future<void> _submit() async {
    await ref
        .read(loginControllerProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(loginControllerProvider);
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
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            enabled: !isSubmitting,
            decoration: const InputDecoration(
              labelText: 'Adresse email',
              hintText: 'vous@exemple.fr',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _canSubmit ? _submit() : null,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _passwordController,
            labelText: 'Mot de passe',
            autofillHints: const [AutofillHints.password],
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
                : const Text('Se connecter'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/forgot-password'),
            child: const Text('Mot de passe oublié ?'),
          ),
          TextButton(
            onPressed: () => context.go('/signup'),
            child: const Text('Créer un compte'),
          ),
          const SizedBox(height: 16),
          _PrivacyLink(),
        ],
      ),
    );
  }
}

class _PrivacyLink extends StatefulWidget {
  @override
  State<_PrivacyLink> createState() => _PrivacyLinkState();
}

class _PrivacyLinkState extends State<_PrivacyLink> {
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
    return Center(
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: 'Politique de confidentialité',
              style: TextStyle(
                color: colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              recognizer: _recognizer,
            ),
          ],
        ),
      ),
    );
  }
}
