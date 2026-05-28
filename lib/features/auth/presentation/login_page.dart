import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';
import '../domain/login_form_state.dart';
import 'widgets/login_form.dart';
import 'widgets/magic_link_sent_view.dart';

/// Page de connexion (magic link uniquement).
///
/// Compose [LoginForm] ou [MagicLinkSentView] selon [LoginFormState].
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formState = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // En-tête
                  Text(
                    'EasyRent',
                    style: Theme.of(context).textTheme.displayMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connectez-vous pour gérer vos locations',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Corps principal selon l'état
                  formState.when(
                    idle: () => const LoginForm(),
                    submitting: () => const LoginForm(),
                    error: (_) => const LoginForm(),
                    linkSent: (email) => MagicLinkSentView(email: email),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
