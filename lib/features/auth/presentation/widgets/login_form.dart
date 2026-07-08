import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/utils/email_validator.dart';
import '../../application/login_controller.dart';
import '../../domain/auth_cta_label.dart';
import '../../domain/auth_error.dart';
import '../auth_cta_label_l10n.dart';
import '../auth_error_l10n.dart';
import 'apple_sign_in_button.dart';
import 'google_sign_in_button.dart';
import 'or_divider.dart';
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

  // Marque quel bouton a déclenché la dernière requête de connexion. Le
  // controller `loginControllerProvider` partage un état `submitting` unique
  // entre l'email/password, Google et Apple ; sans ces flags, plusieurs
  // boutons afficheraient un spinner simultané — perturbe l'UX et suggère
  // que plusieurs flows s'exécutent en parallèle.
  //
  // NB : on garde deux bool distincts (plutôt qu'un enum {none,email,google,
  // apple}) pour rester un mirroir strict et minimal du pattern Google
  // existant — un refactor enum toucherait aussi signup_form.dart et
  // introduirait un diff plus large que nécessaire pour ce ticket. À
  // reconsidérer si un 3e provider OAuth est ajouté un jour (le nombre de
  // bool deviendrait difficile à maintenir en synchronisation).
  bool _googleClickedLast = false;
  bool _appleClickedLast = false;

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
    setState(() {
      _googleClickedLast = false;
      _appleClickedLast = false;
    });
    await ref
        .read(loginControllerProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _googleClickedLast = true;
      _appleClickedLast = false;
    });
    await ref.read(loginControllerProvider.notifier).signInWithGoogle();
  }

  Future<void> _submitApple() async {
    setState(() {
      _appleClickedLast = true;
      _googleClickedLast = false;
    });
    await ref.read(loginControllerProvider.notifier).signInWithApple();
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(loginControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorCode = formState.maybeWhen(
      error: (msg, ctaRoute, ctaLabel) => msg,
      orElse: () => null,
    );
    final errorMessage = errorCode != null
        ? AuthError.fromCode(errorCode).message(context)
        : null;
    final errorCta = formState.maybeWhen(
      error: (msg, ctaRoute, ctaLabel) {
        final label = AuthCtaLabel.fromCode(ctaLabel);
        return (ctaRoute != null && label != null)
            ? (ctaRoute, label.label(context))
            : null;
      },
      orElse: () => null,
    );
    final theme = Theme.of(context);
    final l10n = context.l10n;

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
            decoration: InputDecoration(
              labelText: l10n.authEmailLabel,
              hintText: l10n.authEmailHint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _canSubmit ? _submit() : null,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _passwordController,
            labelText: l10n.authPasswordLabel,
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
            if (errorCta != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('login_error_cta_button'),
                  onPressed: () => context.go(errorCta.$1),
                  child: Text(errorCta.$2),
                ),
              ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_canSubmit && !isSubmitting) ? _submit : null,
            child: (isSubmitting && !_googleClickedLast && !_appleClickedLast)
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : Text(l10n.authSignInButton),
          ),
          const OrDivider(),
          GoogleSignInButton(
            onPressed: isSubmitting ? null : _submitGoogle,
            isLoading: isSubmitting && _googleClickedLast,
          ),
          const SizedBox(height: 12),
          AppleSignInButton(
            onPressed: isSubmitting ? null : _submitApple,
            isLoading: isSubmitting && _appleClickedLast,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/forgot-password'),
            child: Text(l10n.authForgotPasswordLink),
          ),
          TextButton(
            onPressed: () => context.go('/signup'),
            child: Text(l10n.authCreateAccountLink),
          ),
          const SizedBox(height: 16),
          const _PrivacyLink(),
        ],
      ),
    );
  }
}

class _PrivacyLink extends StatefulWidget {
  const _PrivacyLink();

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
              text: context.l10n.authPrivacyPolicyLink,
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
