import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import 'widgets/reset_password_form.dart';

/// Page de réinitialisation du mot de passe.
///
/// Accessible via le lien envoyé par email Firebase :
///   `https://.../reset-password?mode=resetPassword&oobCode=<code>`
///
/// Contrairement à Supabase, Firebase ne crée pas de session "recovery"
/// quand l'utilisateur clique le lien — il fournit juste un `oobCode`
/// (one-time code) qu'on valide via [verifyPasswordResetCode] avant de
/// poser le nouveau password via [confirmPasswordReset].
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  late final String _oobCode;
  Future<String>? _verifyFuture;

  @override
  void initState() {
    super.initState();
    _oobCode = Uri.base.queryParameters['oobCode'] ?? '';
    if (_oobCode.isNotEmpty) {
      _verifyFuture = ref
          .read(authRepositoryProvider)
          .verifyPasswordResetCode(_oobCode);
    }
  }

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
                    'Nouveau mot de passe',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  if (_oobCode.isEmpty)
                    const _InvalidLinkView()
                  else
                    FutureBuilder<String>(
                      future: _verifyFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snap.hasError) {
                          return const _InvalidLinkView();
                        }
                        return ResetPasswordForm(oobCode: _oobCode);
                      },
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

class _InvalidLinkView extends StatelessWidget {
  const _InvalidLinkView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.link_off_outlined, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 24),
        Text(
          'Lien invalide ou expiré',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Ce lien de réinitialisation est invalide ou a expiré. '
          'Demandez-en un nouveau.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => context.go('/forgot-password'),
          child: const Text('Demander un nouveau lien'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Retour à la connexion'),
        ),
      ],
    );
  }
}

