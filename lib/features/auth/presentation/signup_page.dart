import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/signup_controller.dart';
import 'widgets/signup_confirmation_sent_view.dart';
import 'widgets/signup_form.dart';

/// Page de création de compte (self-service).
class SignupPage extends ConsumerWidget {
  const SignupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(signupControllerProvider);
    final showConfirmation = pageState.maybeWhen(
      awaitingConfirmation: () => true,
      orElse: () => false,
    );

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
                    'EasyRent',
                    style: Theme.of(context).textTheme.displayMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Créez votre compte bailleur',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  if (showConfirmation)
                    const SignupConfirmationSentView()
                  else
                    const SignupForm(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
