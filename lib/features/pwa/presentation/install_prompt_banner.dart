import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/l10n_extensions.dart';
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
    final l10n = context.l10n;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) =>
          SizeTransition(sizeFactor: animation, child: child),
      child: state.when(
        hidden: () => const SizedBox.shrink(key: ValueKey('banner_hidden')),
        visibleNative: () => _BannerCard(
          key: const ValueKey('banner_native'),
          subtitle: l10n.pwaInstallBannerNativeSubtitle,
          buttonLabel: l10n.pwaInstallBannerInstallButton,
          onButton: () =>
              ref.read(installPromptControllerProvider.notifier).trigger(),
          onClose: () =>
              ref.read(installPromptControllerProvider.notifier).dismiss(),
        ),
        visibleIos: () => _BannerCard(
          key: const ValueKey('banner_ios'),
          subtitle: l10n.pwaInstallBannerIosSubtitle,
          buttonLabel: l10n.pwaInstallBannerIosConfirmButton,
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
    final l10n = context.l10n;
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
                      l10n.pwaInstallBannerTitle,
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
                tooltip: l10n.commonClose,
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
