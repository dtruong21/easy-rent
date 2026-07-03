import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info/app_info_provider.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import 'widgets/profile_support_form.dart';

/// Page `/profile/support` — formulaire « Nous contacter » (FEAT-025).
///
/// Ne pas présenter ce canal comme une « solution RGPD » dans l'UI (texte
/// volontairement neutre) — voir les notes légales de la story
/// `docs/backlog/025-settings-profile.md`.
class SupportPage extends ConsumerWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Réchauffe appInfoProvider dès le montage de la page : ProfileSupportForm
    // le lit en synchrone (ref.read) au moment du submit, or un
    // FutureProvider fraîchement instancié reste en `loading` le temps d'un
    // tour de boucle d'événements — sans ce watch en amont, un clic très
    // rapide sur « Envoyer » enverrait `appVersion: 'inconnue'`. Sur l'ancien
    // /profile monolithique, ce warm-up se faisait implicitement via
    // ProfileAboutSection montée plus haut sur la même page ; le split en
    // sous-pages a rendu ce couplage caché explicite.
    ref.watch(appInfoProvider);

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppAppBar(title: 'Nous contacter', fallbackRoute: '/profile'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Une question, un souci ? Écrivez-nous.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                const ProfileSupportForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
