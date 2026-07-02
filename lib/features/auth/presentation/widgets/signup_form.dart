import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/email_validator.dart';
import '../../../../core/utils/password_validator.dart';
import '../../application/signup_controller.dart';
import 'apple_sign_in_button.dart';
import 'google_sign_in_button.dart';
import 'or_divider.dart';
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

  /// Erreur "consentement manquant" affichée près de la checkbox quand
  /// l'utilisateur clique un bouton de soumission sans avoir coché la case.
  /// Les boutons restent TOUJOURS cliquables (un bouton mort sans
  /// explication n'est pas compris — retour utilisateur 2026-07-02) : le
  /// consentement est vérifié au clic, jamais implicite. Reset dès que la
  /// case est cochée.
  bool _consentError = false;

  /// Ancre pour ramener la checkbox à l'écran quand l'erreur de
  /// consentement se déclenche depuis un bouton plus bas dans le scroll.
  final _consentKey = GlobalKey();

  // Marque quel bouton a déclenché la dernière requête. Le controller
  // `signupControllerProvider` partage un état `submitting` unique entre
  // email/password, Google et Apple ; ces flags évitent que plusieurs
  // boutons spinnent simultanément. Voir _LoginFormState pour le même
  // pattern et l'arbitrage bool-vs-enum.
  bool _googleClickedLast = false;
  bool _appleClickedLast = false;

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

  // Le consentement RGPD ne conditionne volontairement PAS _canSubmit : il
  // est vérifié au clic via _ensureConsent, qui explique au lieu de
  // désactiver silencieusement.
  bool get _canSubmit =>
      _fullNameController.text.trim().isNotEmpty &&
      EmailValidator.isValid(_emailController.text) &&
      PasswordValidator.validate(_passwordController.text) == null &&
      _passwordController.text == _confirmPasswordController.text;

  /// Vérifie le consentement RGPD au moment du clic. Si absent : affiche
  /// l'erreur près de la checkbox, la ramène à l'écran, et bloque la
  /// soumission (le controller re-vérifie de toute façon — défense en
  /// profondeur).
  bool _ensureConsent() {
    if (_rgpdConsent) return true;
    setState(() => _consentError = true);
    final ctx = _consentKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.5,
      );
    }
    return false;
  }

  Future<void> _submit() async {
    if (!_ensureConsent()) return;
    setState(() {
      _googleClickedLast = false;
      _appleClickedLast = false;
    });
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

  Future<void> _submitGoogle() async {
    if (!_ensureConsent()) return;
    setState(() {
      _googleClickedLast = true;
      _appleClickedLast = false;
    });
    await ref
        .read(signupControllerProvider.notifier)
        .signUpWithGoogle(rgpdConsent: _rgpdConsent);
  }

  Future<void> _submitApple() async {
    if (!_ensureConsent()) return;
    setState(() {
      _appleClickedLast = true;
      _googleClickedLast = false;
    });
    await ref
        .read(signupControllerProvider.notifier)
        .signUpWithApple(rgpdConsent: _rgpdConsent);
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(signupControllerProvider);
    final isSubmitting = formState.maybeWhen(
      submitting: () => true,
      orElse: () => false,
    );
    final errorMessage = formState.maybeWhen(
      error: (msg, ctaRoute, ctaLabel) => msg,
      orElse: () => null,
    );
    final errorCta = formState.maybeWhen(
      error: (msg, ctaRoute, ctaLabel) =>
          (ctaRoute != null && ctaLabel != null) ? (ctaRoute, ctaLabel) : null,
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
            if (errorCta != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('signup_error_cta_button'),
                  onPressed: () => context.go(errorCta.$1),
                  child: Text(errorCta.$2),
                ),
              ),
          ],
          const SizedBox(height: 16),
          _RgpdCheckbox(
            key: _consentKey,
            value: _rgpdConsent,
            enabled: !isSubmitting,
            hasError: _consentError,
            onChanged: (v) => setState(() {
              _rgpdConsent = v ?? false;
              if (_rgpdConsent) _consentError = false;
            }),
          ),
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
                : const Text('Créer mon compte'),
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
    this.hasError = false,
    super.key,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  /// Consentement requis mais absent au moment d'une soumission : encadre
  /// la case en oxblood et affiche le message d'explication dessous.
  final bool hasError;

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    _recognizer.onTap = () => context.go('/privacy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.hasError
                  ? colorScheme.error
                  : const Color(0x00000000),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: widget.value,
                isError: widget.hasError,
                onChanged: widget.enabled ? widget.onChanged : null,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium,
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
          ),
        ),
        if (widget.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              'Vous devez accepter la politique de confidentialité.',
              key: const Key('rgpd_consent_error'),
              style: TextStyle(color: colorScheme.error, fontSize: 13),
            ),
          ),
      ],
    );
  }
}
