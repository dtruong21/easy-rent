import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../auth/application/auth_session_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../application/landlord_profile_provider.dart';
import 'widgets/profile_settings_sections.dart';
import 'widgets/section_header.dart';

/// Page `/profile` — hub de réglages, mobile-first.
///
/// Remplace l'ancien long formulaire empilé par une liste courte et
/// scannable de tuiles de navigation vers des sous-pages dédiées :
/// - `/profile/details` : informations personnelles (identité bailleur)
/// - `/profile/password` : changement de mot de passe (comptes email
///   uniquement — tuile masquée sinon, via [hasPasswordProvider])
/// - `/profile/support` : formulaire « Nous contacter »
///
/// Restent inline dans le hub (contenus légers, pas besoin de sous-page) :
/// Apparence (sélecteur de thème), À propos (version), Session
/// (déconnexion).
///
/// Cette structure plate en tuiles est pensée pour se transposer telle
/// quelle vers l'app mobile iOS/Android (FEAT-024).
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppAppBar(title: 'Mon profil', fallbackRoute: '/dashboard'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ProfileHeader(),
            const SizedBox(height: 32),

            const SectionHeader(title: 'Compte'),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('tile_profile_details'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: const Text('Informations personnelles'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/details'),
            ),
            if (ref.watch(hasPasswordProvider))
              ListTile(
                key: const Key('tile_change_password'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: const Text('Changer le mot de passe'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/password'),
              ),
            const SizedBox(height: 32),

            const ProfileAppearanceSection(),
            const SizedBox(height: 32),

            const SectionHeader(title: 'Aide'),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('tile_support'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.support_agent),
              title: const Text('Nous contacter'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/support'),
            ),
            const ProfileLegalTiles(),
            const SizedBox(height: 24),

            const ProfileAboutSection(),
            const SizedBox(height: 32),

            const ProfileSessionSection(),
          ],
        ),
      ),
    );
  }
}

/// En-tête compact du hub : nom complet + email du bailleur.
///
/// Consomme [landlordProfileProvider], mais reste tolérant loading/erreur :
/// pas de spinner bloquant pleine page — l'email de [authRepositoryProvider]
/// (toujours disponible dès qu'on est fullyAuthenticated) sert de fallback
/// pendant le chargement ou en cas d'échec réseau.
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncProfile = ref.watch(landlordProfileProvider);
    final authEmail = ref.watch(authRepositoryProvider).currentUser?.email;

    final fullName = asyncProfile.asData?.value.fullName;
    final email = asyncProfile.asData?.value.email ?? authEmail ?? '';

    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.person,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fullName != null && fullName.isNotEmpty)
                Text(
                  fullName,
                  key: const Key('txt_profile_header_name'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                email,
                key: const Key('txt_profile_header_email'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
