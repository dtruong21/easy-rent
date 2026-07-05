import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/install_prompt_controller.dart';

/// Banner Material 3 affichant le prompt d'installation PWA.
///
/// S'affiche en haut du dashboard si [InstallPromptState] est
/// [visibleNative] ou [visibleIos]. Disparaît sinon.
///
/// Variante native : bouton "Installer" → déclenche le prompt navigateur.
/// Variante iOS    : instructions textuelles + bouton "OK, compris".
class InstallPromptBanner extends ConsumerWidget {
  const InstallPromptBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(installPromptControllerProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) =>
          SizeTransition(sizeFactor: animation, child: child),
      child: state.when(
        hidden: () => const SizedBox.shrink(key: ValueKey('banner_hidden')),
        visibleNative: () => _BannerCard(
          key: const ValueKey('banner_native'),
          subtitle:
              'Accédez à votre gestion locative en un clic, même hors-ligne.',
          buttonLabel: 'Installer',
          onButton: () =>
              ref.read(installPromptControllerProvider.notifier).trigger(),
          onClose: () =>
              ref.read(installPromptControllerProvider.notifier).dismiss(),
        ),
        visibleIos: () => _BannerCard(
          key: const ValueKey('banner_ios'),
          subtitle: 'Appuyez sur Partager puis « Sur l\'écran d\'accueil ».',
          buttonLabel: 'OK, compris',
          onButton: () =>
              ref.read(installPromptControllerProvider.notifier).dismiss(),
          onClose: () =>
              ref.read(installPromptControllerProvider.notifier).dismiss(),
        ),
        triggering: () => const _BannerLoading(key: ValueKey('banner_loading')),
        installed: () =>
            const SizedBox.shrink(key: ValueKey('banner_installed')),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sous-widgets
// ---------------------------------------------------------------------------

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    super.key,
    required this.subtitle,
    required this.buttonLabel,
    required this.onButton,
    required this.onClose,
  });

  final String subtitle;
  final String buttonLabel;
  final VoidCallback onButton;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: Card(
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.install_mobile_outlined,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Installez Baillan.',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onButton,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(buttonLabel),
              ),
              IconButton(
                key: const Key('btn_banner_close'),
                icon: const Icon(Icons.close),
                tooltip: 'Fermer',
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerLoading extends StatelessWidget {
  const _BannerLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
