import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/widgets/anon_demo_banner.dart';
import 'widgets/landing_sheet.dart';

final _log = Logger('LandingPage');

/// Page d'accueil publique — « La Page de Garde » (BAILLAN-M1, redesign
/// 2026-07-02).
///
/// Même univers que la login page (« La Page du Registre ») : la couverture
/// du registre est un feuillet crème posé sur un bureau d'encre. Le bureau
/// s'inverse avec le mode sombre, la feuille reste papier (thème light forcé
/// dans son sous-arbre — un objet physique ne s'inverse pas). Animation
/// d'entrée fade-up + tracé des filets, sautée si `prefers-reduced-motion`.
///
/// Route `/`. Seul un visiteur `unauthenticated` voit réellement cette page
/// (le router redirige `anonymous` → `/simulator` et `fullyAuthenticated`
/// → `/dashboard`).
///
/// 2 CTA égaux : « Continuer sans compte » (Firebase Anonymous Auth →
/// `/simulator`) et « Créer un compte » (`/signup`), plus un lien discret
/// « J'ai déjà un compte » (`/login`).
class LandingPage extends ConsumerStatefulWidget {
  const LandingPage({super.key});

  @override
  ConsumerState<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends ConsumerState<LandingPage>
    with SingleTickerProviderStateMixin {
  static const _kDesktopBreakpoint = 900.0;
  static const _kSheetMaxWidth = 720.0;

  late final AnimationController _controller;
  late final Animation<double> _sheetFade;
  late final Animation<Offset> _sheetSlide;
  late final Animation<double> _ruleDraw;

  bool _animationsStarted = false;
  bool _isStartingAnonymous = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // La feuille se pose d'abord (0 → 0.55)…
    _sheetFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );
    _sheetSlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
          ),
        );
    // …puis les filets se tracent (0.45 → 1.0).
    _ruleDraw = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.0, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect de `prefers-reduced-motion` : on saute à l'état final. Lu ici
    // (pas dans initState) car MediaQuery n'y est pas disponible.
    if (_animationsStarted) return;
    _animationsStarted = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continueWithoutAccount() async {
    setState(() => _isStartingAnonymous = true);
    try {
      await ref.read(authRepositoryProvider).signInAnonymously();
      // Succès : le changement de sessionState déclenche le refresh du
      // router (ref.listen dans appRouterProvider) → redirection
      // automatique vers /simulator. On garde le context.go explicite pour
      // un rendu instantané (évite d'attendre le prochain tick du
      // StreamProvider dans les tests widget / connexions lentes).
      if (mounted) context.go('/simulator');
    } on FirebaseAuthException catch (e, st) {
      _log.warning('signInAnonymously failed (code=${e.code})', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.landingAnonymousSignInErrorSnackbar),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStartingAnonymous = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Le bureau s'inverse selon l'ambiance ; la feuille, jamais.
    final deskColor = isDark ? AppTheme.ink : AppTheme.paperDeep;
    final folioColor = isDark ? AppTheme.oliveSoft : AppTheme.inkMuted;

    return Scaffold(
      backgroundColor: deskColor,
      body: SafeArea(
        child: Column(
          children: [
            const AnonDemoBanner(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= _kDesktopBreakpoint;
                  // Thème LIGHT forcé : les boutons olive et l'encre de la
                  // feuille restent identiques quel que soit le mode ambiant.
                  return Theme(
                    data: AppTheme.light,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 40 : 16,
                        vertical: isDesktop ? 48 : 24,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              constraints.maxHeight -
                              (isDesktop ? 96 : 48), // compense le padding
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _kSheetMaxWidth,
                            ),
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) {
                                return FadeTransition(
                                  opacity: _sheetFade,
                                  child: SlideTransition(
                                    position: _sheetSlide,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        LandingSheet(
                                          isDesktop: isDesktop,
                                          isAmbientDark: isDark,
                                          ruleDraw: _ruleDraw,
                                          isStartingAnonymous:
                                              _isStartingAnonymous,
                                          onContinueWithoutAccount:
                                              _continueWithoutAccount,
                                          onCreateAccount: () =>
                                              context.go('/signup'),
                                          onLogin: () => context.go('/login'),
                                        ),
                                        const SizedBox(height: 18),
                                        // Folio sous la feuille — vit sur le
                                        // bureau, s'adapte à l'ambiance.
                                        Center(
                                          child: Text(
                                            context.l10n.landingFolioCaption,
                                            style: TextStyle(
                                              fontFamily: 'EB Garamond',
                                              fontFamilyFallback: serifFallback,
                                              fontStyle: FontStyle.italic,
                                              fontSize: 12,
                                              letterSpacing: 1.2,
                                              color: folioColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
