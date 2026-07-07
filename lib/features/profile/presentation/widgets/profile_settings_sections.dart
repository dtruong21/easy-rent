// Sections « réglages » du hub /profile : apparence (thème), tuiles légales,
// à propos (version) et déconnexion. Extraites de ProfilePage pour garder la
// page sous la limite de 200 lignes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/app_info/app_info_provider.dart';
import '../../../../core/config/env.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../auth/application/login_controller.dart';
import 'section_header.dart';

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
        const SectionHeader(title: 'Apparence'),
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

/// Tuiles vers les pages légales (`/terms`, `/privacy`).
///
/// Pas de [SectionHeader] ici : ces tuiles sont insérées par [ProfilePage]
/// dans son propre groupe « Aide », partagé avec la tuile support — un seul
/// header pour tout le groupe, pas de duplication.
///
/// `push` (et non `go`) : la page profil reste dans la pile, le retour
/// revient ici.
class ProfileLegalTiles extends StatelessWidget {
  const ProfileLegalTiles({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
// À propos — version + environnement
// ---------------------------------------------------------------------------

/// Version de l'app (semver + numéro de build) et environnement courant.
///
/// Permet de vérifier quel déploiement on a sous les yeux — indispensable
/// pour tester staging vs prod (voir la convention dans pubspec.yaml).
class ProfileAboutSection extends ConsumerWidget {
  const ProfileAboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncInfo = ref.watch(appInfoProvider);

    final versionLabel = asyncInfo.when(
      data: (info) => 'v${info.version} (build ${info.buildNumber})',
      loading: () => '…',
      error: (_, _) => 'version inconnue',
    );
    final envLabel = Env.isProd ? 'production' : 'dev/staging';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'À propos'),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              'Baillan. $versionLabel · $envLabel',
              key: const Key('txt_app_version'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
        const SectionHeader(title: 'Session'),
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
// Suppression du compte (FEAT-045)
// ---------------------------------------------------------------------------

/// Tuile d'accès au flux de suppression de compte.
///
/// Exigence stores (Play « Account deletion » / App Store 5.1.1(v)) : le
/// point d'entrée doit être facile à trouver — dernière section du hub
/// /profile, style destructif. Tout l'avertissement (conséquences,
/// rétention quittances) vit sur la sous-page dédiée.
class ProfileDeleteAccountSection extends StatelessWidget {
  const ProfileDeleteAccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Suppression du compte'),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('tile_delete_account'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_forever_outlined,
            color: colorScheme.error,
          ),
          title: Text(
            'Supprimer mon compte',
            style: TextStyle(color: colorScheme.error),
          ),
          subtitle: const Text('Suppression définitive de vos données'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/profile/delete-account'),
        ),
      ],
    );
  }
}
