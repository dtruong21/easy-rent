// Sections « réglages » de la page profil : apparence (thème), liens
// légaux et déconnexion. Extraites de ProfilePage pour garder la page
// sous la limite de 200 lignes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/theme_mode_provider.dart';
import '../../../auth/application/login_controller.dart';

// ---------------------------------------------------------------------------
// Apparence — choix du thème
// ---------------------------------------------------------------------------

/// Sélecteur de thème (Système / Clair / Sombre), persisté via
/// [themeModeProvider].
class ProfileAppearanceSection extends ConsumerWidget {
  const ProfileAppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Apparence'),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(
          key: const Key('segments_theme_mode'),
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Système')),
            ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              ref.read(themeModeProvider.notifier).setMode(selection.first);
            }
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Légal — CGU + politique de confidentialité
// ---------------------------------------------------------------------------

/// Liens vers les pages légales (`/terms`, `/privacy`).
///
/// `push` (et non `go`) : la page profil reste dans la pile, le retour
/// revient ici.
class ProfileLegalSection extends StatelessWidget {
  const ProfileLegalSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Légal'),
        ListTile(
          key: const Key('tile_terms'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.gavel_outlined),
          title: const Text("Conditions générales d'utilisation"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/terms'),
        ),
        ListTile(
          key: const Key('tile_privacy'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Politique de confidentialité'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/privacy'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Session — déconnexion
// ---------------------------------------------------------------------------

/// Bouton de déconnexion. Après [signOut], la garde du routeur redirige
/// automatiquement vers /login (changement de sessionState).
class ProfileSessionSection extends ConsumerWidget {
  const ProfileSessionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Session'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('btn_logout_profile'),
          onPressed: () => ref.read(loginControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Se déconnecter'),
          style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header de section
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
