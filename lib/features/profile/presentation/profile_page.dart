import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/config/store_billing.dart';
import '../../../core/i18n/l10n_extensions.dart';
import '../../../core/ui/app_bar/app_app_bar.dart';
import '../../auth/application/auth_session_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/landlord_tier_repository.dart';
import '../../auth/domain/plan_level.dart';
import '../../paid_plan/presentation/pro_badge.dart';
import '../../paid_plan/presentation/widgets/subscription_section.dart';
import '../../account/presentation/widgets/export_data_tile.dart';
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
/// - `/profile/delete-account` : suppression de compte (FEAT-045 — exigence
///   stores : point d'entrée facile à trouver, dans le groupe « Compte »)
/// - `/faq` : questions fréquentes (page publique)
/// - `/profile/support` : formulaire « Nous contacter »
///
/// Ordre des groupes (décision 2026-07-07) : Compte (identité, mot de
/// passe, suppression) → Apparence → Aide (FAQ, contact, légal) →
/// À propos → Session.
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppAppBar(title: l10n.profileHubTitle, showBackButton: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ProfileHeader(),
            const SizedBox(height: 16),
            const _ProUpsellCard(),
            const SizedBox(height: 32),

            SectionHeader(title: l10n.profileHubAccountSection),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('tile_profile_details'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(l10n.profileHubPersonalInfoTile),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/details'),
            ),
            if (ref.watch(hasPasswordProvider))
              ListTile(
                key: const Key('tile_change_password'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.profileHubChangePasswordTile),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/password'),
              ),
            // Export RGPD (droit à la portabilité, art. 20) : juste avant la
            // suppression de compte — ordre logique (consulter avant de
            // supprimer).
            const ExportDataTile(),
            // Suppression de compte (FEAT-045) : dans le groupe Compte —
            // facile à trouver (exigence stores), style destructif.
            ListTile(
              key: const Key('tile_delete_account'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_forever_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(
                l10n.profileHubDeleteAccountTile,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/delete-account'),
            ),
            const SizedBox(height: 32),

            // Résiliation/réactivation d'abonnement (FEAT-044f, conformité
            // art. L215-1-1) — le widget s'auto-masque pour les non-abonnés
            // (porte lui-même son espacement final quand visible, même
            // convention que ProfileCrashReportingSection), donc aucune
            // condition ni SizedBox supplémentaire ici.
            const SubscriptionSection(),

            const ProfileAppearanceSection(),
            const SizedBox(height: 32),

            const ProfileLanguageSection(),
            const SizedBox(height: 32),

            // Rapport d'incident (Crashlytics) — visible seulement sur mobile
            // (rendu vide sur le web via kIsWeb).
            const ProfileCrashReportingSection(),

            SectionHeader(title: l10n.profileHubHelpSection),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('tile_faq'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.help_outline),
              title: Text(l10n.profileFaqTile),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/faq'),
            ),
            ListTile(
              key: const Key('tile_support'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.support_agent),
              title: Text(l10n.profileHubContactUsTile),
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        fullName,
                        key: const Key('txt_profile_header_name'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ProBadge(),
                  ],
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

/// La bannière « Passer à Pro » doit-elle s'afficher ? Oui seulement si les
/// abonnements sont ouverts ([Env.subscriptionsEnabled]), hors apps iOS/Android
/// ([isStoreApp] : aucun chemin d'achat hors achat intégré) et pour un compte
/// pas encore payant. Fonction pure : `Env.subscriptionsEnabled` est figé à la
/// compilation, elle rend la règle testable dans les deux états.
@visibleForTesting
bool proUpsellVisible({
  required bool subscriptionsEnabled,
  required bool storeApp,
  required bool isPaid,
}) => subscriptionsEnabled && !storeApp && !isPaid;

/// Bannière « Passer à Pro » — masquée tant que [Env.subscriptionsEnabled]
/// vaut `false` (freemium MVP, juillet 2026) : inutile de faire la publicité
/// d'un abonnement impossible à souscrire (le checkout Stripe est lui-même
/// masqué sur `/pro`, cf. `ProPricingPage`), et toujours masquée dans les apps
/// iOS/Android (cf. [proUpsellVisible]). Les gates fonctionnels (limite
/// de scénarios, comparaison) restent inchangés — eux expliquent une
/// limitation réelle, pas une simple incitation commerciale.
class _ProUpsellCard extends ConsumerWidget {
  const _ProUpsellCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaid = ref.watch(planEntitlementProvider).atLeast(PlanLevel.pro);
    if (!proUpsellVisible(
      subscriptionsEnabled: Env.subscriptionsEnabled,
      storeApp: isStoreApp,
      isPaid: isPaid,
    )) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/pro'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.star, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.proUpgradeButton,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
