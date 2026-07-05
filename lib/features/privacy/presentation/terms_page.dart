import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';

/// Page des conditions générales d'utilisation (CGU).
///
/// Accessible sans login (route `/terms` publique).
/// Référencée depuis [ProfilePage] (section Légal).
///
/// Dernière mise à jour : juillet 2026
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppAppBar(
        title: "Conditions générales d'utilisation",
        fallbackRoute: '/',
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: _TermsContent(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contenu
// ---------------------------------------------------------------------------

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Conditions générales d'utilisation",
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Version 1.0 — Dernière mise à jour : juillet 2026',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),

        // 1. Objet
        const _Section(
          title: '1. Objet',
          body:
              'Baillan. est un outil de gestion locative destiné aux bailleurs '
              'particuliers : suivi des biens, locataires, baux et paiements, '
              'génération de quittances de loyer et stockage de documents.\n\n'
              "L'utilisation du service vaut acceptation pleine et entière des "
              'présentes conditions générales.',
        ),

        // 2. Accès au service
        const _Section(
          title: '2. Accès au service',
          body:
              "L'accès complet au service nécessite la création d'un compte "
              '(email et mot de passe, ou fournisseur Google / Apple). '
              "L'utilisateur est responsable de la confidentialité de ses "
              "identifiants et des actions effectuées depuis son compte.\n\n"
              "Un mode d'essai sans compte (session anonyme) donne accès au "
              "simulateur d'investissement pendant 14 jours glissants. Les "
              "données d'essai sont supprimées automatiquement à expiration ; "
              "la création d'un compte pendant l'essai les conserve.",
        ),

        // 3. Obligations de l'utilisateur
        const _Section(
          title: "3. Obligations de l'utilisateur",
          body:
              "L'utilisateur s'engage à :\n\n"
              '• saisir des informations exactes et à jour (montants, dates, '
              'identités des locataires) ;\n\n'
              "• utiliser le service dans le respect de la loi, en qualité de "
              'bailleur, pour la gestion de ses propres biens ;\n\n'
              '• respecter ses obligations légales et contractuelles envers ses '
              'locataires, dont il demeure seul responsable.',
        ),

        // 4. Documents générés
        const _Section(
          title: '4. Documents générés',
          body:
              'Les quittances de loyer sont générées à partir des données '
              "saisies par l'utilisateur, selon le formalisme de l'article 21 "
              'de la loi n° 89-462 du 6 juillet 1989.\n\n'
              "Baillan. est un outil d'aide à la gestion : il ne constitue ni "
              'un conseil juridique, ni un service de rédaction d\'actes. '
              "L'utilisateur reste responsable du contenu des documents émis "
              'sous son nom et de leur remise aux locataires.',
        ),

        // 5. Données personnelles
        const _Section(
          title: '5. Données personnelles',
          body:
              'Le traitement des données personnelles est décrit dans la '
              'politique de confidentialité, accessible depuis le service.\n\n'
              'Chaque bailleur est responsable de traitement, au sens du RGPD, '
              'des données de ses locataires saisies dans Baillan.',
        ),

        // 6. Disponibilité
        const _Section(
          title: '6. Disponibilité du service',
          body:
              "Le service est fourni « en l'état ». L'éditeur met en œuvre des "
              'efforts raisonnables pour assurer sa disponibilité et la '
              'sauvegarde des données, sans garantie de continuité absolue '
              '(maintenance, incident, cas de force majeure).\n\n'
              "L'utilisateur est invité à conserver une copie des documents "
              'importants (quittances, baux signés) en dehors du service.',
        ),

        // 7. Propriété intellectuelle
        const _Section(
          title: '7. Propriété intellectuelle',
          body:
              "L'application Baillan., sa marque, son interface et son code "
              "restent la propriété exclusive de l'éditeur.\n\n"
              "Les données et documents saisis ou importés par l'utilisateur "
              'restent sa propriété. Il concède à l\'éditeur le seul droit '
              'technique de les héberger et de les traiter pour fournir le '
              'service.',
        ),

        // 8. Résiliation
        const _Section(
          title: '8. Résiliation et suppression de compte',
          body:
              "L'utilisateur peut cesser d'utiliser le service et demander la "
              'suppression de son compte à tout moment (droit à '
              "l'effacement — RGPD art. 17).\n\n"
              'Les documents soumis à une obligation légale de conservation '
              '(quittances : 5 ans après la fin du bail) sont conservés '
              "jusqu'à l'échéance légale avant suppression définitive.\n\n"
              "L'éditeur peut suspendre un compte en cas de violation "
              'manifeste des présentes conditions, après notification.',
        ),

        // 9. Évolution des conditions
        const _Section(
          title: '9. Évolution des conditions',
          body:
              'Les présentes conditions peuvent évoluer avec le service. La '
              'version en vigueur, datée, est accessible en permanence depuis '
              "l'application. En cas de modification substantielle, les "
              'utilisateurs sont informés dans l\'application.',
        ),

        // 10. Droit applicable
        const _Section(
          title: '10. Droit applicable',
          body:
              'Les présentes conditions sont régies par le droit français. À '
              "défaut de résolution amiable, tout litige relatif à l'usage du "
              'service relève des tribunaux français compétents.',
        ),

        const SizedBox(height: 24),
        // Renvoi vers la politique de confidentialité (RGPD).
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('btn_terms_to_privacy'),
            onPressed: () => context.push('/privacy'),
            icon: const Icon(Icons.privacy_tip_outlined),
            label: const Text('Lire la politique de confidentialité'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
