import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';

/// Page « Mentions légales » — obligation LCEN (art. 6 III, loi n° 2004-575
/// du 21 juin 2004) : identité de l'éditeur + de l'hébergeur accessibles
/// depuis le service.
///
/// Accessible sans login (route `/legal` publique). Référencée depuis
/// [ProfilePage] (section Légal).
///
/// ⚠️ **À COMPLÉTER avant toute release production.** Les coordonnées de
/// l'éditeur (dénomination, statut, SIREN, adresse, contact, directeur de
/// publication) sont des **placeholders** tant que l'entité (micro-entrepreneur)
/// n'est pas immatriculée — cf. `docs/STORE_LAUNCH_CHECKLIST.md` §0/§1. Ne pas
/// promouvoir en prod tant que les mentions `« à compléter »` subsistent.
/// Contenu légal FR (non i18n, cf. `lib/l10n/l10n_convention.dart` §7).
class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(title: 'Mentions légales', fallbackRoute: '/'),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: _LegalContent(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contenu
// ---------------------------------------------------------------------------

class _LegalContent extends StatelessWidget {
  const _LegalContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mentions légales', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Dernière mise à jour : juillet 2026',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        // Bandeau d'avertissement — placeholders à compléter avant prod.
        Container(
          key: const Key('box_legal_placeholder_warning'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.35),
            border: Border.all(color: colorScheme.error),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Brouillon : les coordonnées de l\'éditeur marquées « à compléter » '
            'doivent être renseignées avant la mise en production (LCEN).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 1. Éditeur
        const _Section(
          title: '1. Éditeur du service',
          body:
              'Le service Baillan. (application web et mobile de gestion '
              'locative) est édité par :\n\n'
              '• Dénomination / nom : « à compléter »\n'
              '• Statut juridique : micro-entrepreneur (« à compléter »)\n'
              '• Numéro SIREN / SIRET : « à compléter »\n'
              '• Adresse du siège : « à compléter »\n'
              '• Adresse email de contact : « à compléter »\n'
              '• Téléphone : « à compléter »',
        ),

        // 2. Directeur de la publication
        const _Section(
          title: '2. Directeur de la publication',
          body: 'Le directeur de la publication est : « à compléter ».',
        ),

        // 3. Hébergeur
        const _Section(
          title: '3. Hébergeur',
          body:
              'Le service est hébergé par Google Ireland Limited (Firebase '
              'Hosting / Google Cloud Platform), Gordon House, Barrow Street, '
              'Dublin 4, D04 E5W5, Irlande — pour le compte de Google LLC, '
              '1600 Amphitheatre Parkway, Mountain View, CA 94043, États-Unis.\n\n'
              'Les données applicatives sont localisées dans l\'Union '
              'européenne (Cloud Firestore multi-région eur3 ; Cloud Storage '
              'europe-west3, Francfort).',
        ),

        // 4. Contact
        const _Section(
          title: '4. Contact',
          body:
              'Pour toute question relative au service, utilisez le formulaire '
              '« Nous contacter » accessible depuis votre profil, ou l\'adresse '
              'email de contact indiquée ci-dessus.',
        ),

        // 5. Propriété intellectuelle
        const _Section(
          title: '5. Propriété intellectuelle',
          body:
              'La marque « Baillan. », le logo, l\'interface et le contenu '
              'éditorial du service sont protégés au titre du droit de la '
              'propriété intellectuelle. Toute reproduction ou représentation, '
              'totale ou partielle, sans autorisation préalable, est interdite.\n\n'
              'Les données saisies par chaque utilisateur (biens, locataires, '
              'baux, documents…) restent la propriété de cet utilisateur.',
        ),

        // 6. Données personnelles
        const _Section(
          title: '6. Données personnelles',
          body:
              'Le traitement des données personnelles est décrit dans la '
              'politique de confidentialité.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('btn_legal_to_privacy'),
            onPressed: () => context.push('/privacy'),
            child: const Text('Politique de confidentialité'),
          ),
        ),

        const SizedBox(height: 24),
        Text(
          'Baillan. — Gestion locative simplifiée',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section réutilisable
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
