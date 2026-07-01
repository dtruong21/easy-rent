import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/widgets/anon_demo_banner.dart';
import 'widgets/landing_hero.dart';

final _log = Logger('LandingPage');

/// Page d'accueil publique — carrefour d'onboarding Baillan (BAILLAN-M1).
///
/// Route `/`. Contrairement à l'ancien comportement (dashboard direct), `/`
/// est désormais accessible à tout visiteur, authentifié ou non — le router
/// redirige les sessions actives (`anonymous` → `/simulator`,
/// `fullyAuthenticated` → `/dashboard`) ; seul un visiteur `unauthenticated`
/// voit réellement cette page.
///
/// 2 CTA égaux : « Continuer sans compte » (Firebase Anonymous Auth →
/// `/simulator`) et « Créer un compte » (`/signup`), plus un lien discret
/// « J'ai déjà un compte » (`/login`).
class LandingPage extends ConsumerStatefulWidget {
  const LandingPage({super.key});

  @override
  ConsumerState<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends ConsumerState<LandingPage> {
  bool _isStartingAnonymous = false;

  Future<void> _continueWithoutAccount() async {
    setState(() => _isStartingAnonymous = true);
    try {
      await ref.read(authRepositoryProvider).signInAnonymously();
      // Succès : authStateChanges déclenche GoRouterRefreshStream → le
      // router redirige automatiquement vers /simulator (sessionState
      // devient anonymous). Pas besoin de context.go ici, mais on le fait
      // quand même pour un rendu instantané (évite d'attendre le prochain
      // tick du StreamProvider dans les tests widget / connexions lentes).
      if (mounted) context.go('/simulator');
    } on FirebaseAuthException catch (e, st) {
      _log.warning('signInAnonymously failed (code=${e.code})', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connexion impossible, réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingAnonymous = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Column(
          children: [
            const AnonDemoBanner(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LandingHero(),
                        const SizedBox(height: 48),
                        // Product lock #2 : les 2 CTAs ont un POIDS VISUEL
                        // ÉQUIVALENT (mêmes bordures pleines olive, même
                        // taille, même typo). L'utilisateur doit pouvoir
                        // choisir librement sans qu'une hiérarchie visuelle
                        // le pousse vers "Créer un compte" (défaut FilledB
                        // primary sur OutlinedButton secondary). On rend
                        // les deux Filled + primary olive pour éviter tout
                        // biais UX.
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                key: const Key('landing_cta_anonymous'),
                                onPressed: _isStartingAnonymous
                                    ? null
                                    : _continueWithoutAccount,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                ),
                                child: _isStartingAnonymous
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Continuer sans compte'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: FilledButton(
                                key: const Key('landing_cta_signup'),
                                onPressed: () => context.go('/signup'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                ),
                                child: const Text('Créer un compte'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: TextButton(
                            key: const Key('landing_cta_login'),
                            onPressed: () => context.go('/login'),
                            child: const Text('J\'ai déjà un compte'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
