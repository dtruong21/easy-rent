import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Page de politique de confidentialité (placeholder).
///
/// Contenu provisoire — à compléter par le rédacteur juridique.
/// Référencée depuis la case RGPD de la [LoginPage].
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Politique de confidentialité'),
        leading: BackButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: _PrivacyContent(),
        ),
      ),
    );
  }
}

class _PrivacyContent extends StatelessWidget {
  const _PrivacyContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Politique de confidentialité',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Dernière mise à jour : mai 2026',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        _Section(
          title: 'Responsable du traitement',
          body:
              'EasyRent — [Nom et coordonnées du responsable à compléter]. '
              'Pour toute question relative à vos données personnelles, '
              'contactez-nous à : privacy@easyrent.fr (à compléter).',
        ),
        _Section(
          title: 'Données collectées',
          body:
              'Nous collectons votre adresse email dans le seul but de '
              "vous authentifier sur l'application EasyRent via un lien "
              'à usage unique (magic link). Aucun mot de passe n\'est '
              'stocké.',
        ),
        _Section(
          title: 'Base légale',
          body:
              'Le traitement est fondé sur l\'exécution du contrat (art. 6.1.b '
              'RGPD) : votre email est nécessaire pour vous authentifier '
              'et accéder à votre espace de gestion locative.',
        ),
        _Section(
          title: 'Durée de conservation',
          body:
              'Vos données sont conservées tant que votre compte est actif. '
              'En cas de demande de suppression, nous procéderons à '
              "l'effacement dans les délais légaux, sous réserve des "
              "obligations de conservation (notamment les quittances : "
              '5 ans, art. 2224 Code civil).',
        ),
        _Section(
          title: 'Vos droits',
          body:
              'Conformément au RGPD, vous disposez des droits d\'accès, '
              "de rectification, d'effacement, de portabilité et "
              "d'opposition. Pour les exercer, contactez-nous à l'adresse "
              'indiquée ci-dessus.',
        ),
        _Section(
          title: 'Hébergement',
          body:
              'Les données sont hébergées sur Supabase (infrastructure '
              'AWS EU-West) et Firebase Hosting (Google, UE). '
              '[À détailler lors de la mise en production.]',
        ),
        const SizedBox(height: 32),
        Text(
          'Ce document est provisoire et sera complété avant la mise en '
          'production.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

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
