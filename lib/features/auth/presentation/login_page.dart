import 'package:flutter/material.dart';

import 'widgets/login_form.dart';

/// Page de connexion par email et mot de passe.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                    'Baillan.',
                    style: Theme.of(context).textTheme.displayMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tenir registre.',
                    // Signature de marque sous le wordmark — même stack
                    // sérif italique (Cochin/Palatino) que le mot au-dessus,
                    // mais taille body et couleur muted pour rester discret.
                    // Cadence identique (mot + point).
                    style: TextStyle(
                      fontFamily: 'Cochin',
                      fontFamilyFallback: const [
                        'Palatino Linotype',
                        'Book Antiqua',
                        'Palatino',
                        'Georgia',
                        'serif',
                      ],
                      fontStyle: FontStyle.italic,
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  const LoginForm(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
