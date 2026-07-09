// Sections « réglages » du hub /profile : apparence (thème), tuiles légales,
// à propos (version) et déconnexion. Extraites de ProfilePage pour garder la
// page sous la limite de 200 lignes.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/app_info/app_info_provider.dart';
import '../../../../core/config/env.dart';
import '../../../../core/i18n/l10n_extensions.dart';
import '../../../../core/i18n/locale_provider.dart';
import '../../../../core/observability/crash_reporting_provider.dart';
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
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.profileAppearanceTitle),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(
          key: const Key('segments_theme_mode'),
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(l10n.profileThemeSystem),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text(l10n.profileThemeLight),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text(l10n.profileThemeDark),
            ),
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
// Langue — sélecteur Système / Français / English (FEAT-043)
// ---------------------------------------------------------------------------

/// Sélecteur de langue (Système / Français / English), persisté via
/// [localeProvider]. Calque exact de [ProfileAppearanceSection].
///
/// `null` (Système) = suit la locale du navigateur/OS (résolue par
/// `localeResolutionCallback` dans `main.dart`, fallback FR).
class ProfileLanguageSection extends ConsumerWidget {
  const ProfileLanguageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.profileLanguageTitle),
        const SizedBox(height: 12),
        SegmentedButton<Locale?>(
          key: const Key('segments_locale'),
          segments: [
            ButtonSegment(value: null, label: Text(l10n.profileLanguageSystem)),
            ButtonSegment(
              value: const Locale('fr'),
              label: Text(l10n.profileLanguageFrench),
            ),
            ButtonSegment(
              value: const Locale('en'),
              label: Text(l10n.profileLanguageEnglish),
            ),
          ],
          selected: {locale},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              ref.read(localeProvider.notifier).setLocale(selection.first);
            }
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Confidentialité — consentement rapport d'incident (Crashlytics)
// ---------------------------------------------------------------------------

/// Interrupteur d'opt-in au rapport d'incident (Firebase Crashlytics).
///
/// **Mobile uniquement** : Crashlytics n'a pas d'implémentation web, donc la
/// section n'est PAS rendue sur le web ([kIsWeb] → [SizedBox.shrink]). Opt-in,
/// désactivé par défaut ; piloté par [crashReportingProvider] qui persiste le
/// choix et appelle `setCrashlyticsCollectionEnabled`.
class ProfileCrashReportingSection extends ConsumerWidget {
  const ProfileCrashReportingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Crashlytics = mobile only → rien à afficher sur le web.
    if (kIsWeb) return const SizedBox.shrink();

    final enabled = ref.watch(crashReportingProvider);
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.profileCrashReportingSection),
        SwitchListTile(
          key: const Key('switch_crash_reporting'),
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: (value) =>
              ref.read(crashReportingProvider.notifier).setEnabled(value),
          title: Text(l10n.profileCrashReportingTitle),
          subtitle: Text(l10n.profileCrashReportingSubtitle),
        ),
        // Espacement vers la section suivante — porté par la section elle-même
        // pour rester absent sur le web (où la section n'est pas rendue).
        const SizedBox(height: 32),
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
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: const Key('tile_terms'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.gavel_outlined),
          title: Text(l10n.profileHubTermsTile),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/terms'),
        ),
        ListTile(
          key: const Key('tile_privacy'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l10n.profileHubPrivacyTile),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/privacy'),
        ),
        ListTile(
          key: const Key('tile_legal'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.profileHubLegalTile),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/legal'),
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
    final l10n = context.l10n;
    final asyncInfo = ref.watch(appInfoProvider);

    final versionLabel = asyncInfo.when(
      data: (info) =>
          l10n.profileAboutVersionValue(info.version, info.buildNumber),
      loading: () => '…',
      error: (_, _) => l10n.profileAboutVersionUnknown,
    );
    final envLabel = Env.isProd
        ? l10n.profileAboutEnvProduction
        : l10n.profileAboutEnvDevStaging;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.profileAboutTitle),
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
              l10n.profileAboutSummary(l10n.appTitle, versionLabel, envLabel),
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
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.profileSessionTitle),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('btn_logout_profile'),
          onPressed: () => ref.read(loginControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout),
          label: Text(l10n.profileSessionLogoutButton),
          style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
        ),
      ],
    );
  }
}

// NB (2026-07-07) : la tuile « Supprimer mon compte » (FEAT-045) vit
// désormais dans le groupe « Compte » de ProfilePage — l'ancienne section
// dédiée en fin de hub a été retirée (décision de réordonnancement).
