import 'package:flutter/material.dart';

import '../../../core/ui/app_bar/app_app_bar.dart';

/// Page `/faq` — questions fréquentes sur Baillan.
///
/// Publique (hors shell, comme `/privacy`) : consultable avant de créer un
/// compte, par les sessions d'essai anonymes, et référençable depuis les
/// fiches stores. Également accessible via Profil → Aide → FAQ.
///
/// Contenu statique embarqué (pas de collection Firestore) : la FAQ évolue
/// avec le produit, au rythme des releases — même logique que `/privacy` et
/// `/terms`.
class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppAppBar(title: 'Questions fréquentes', fallbackRoute: '/'),
      body: SafeArea(
        child: Center(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FAQ — Baillan',
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Les réponses aux questions les plus fréquentes. Vous '
                        'ne trouvez pas la vôtre ? Écrivez-nous via '
                        'Profil → Aide → « Nous contacter ».',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final (index, entry) in _faqEntries.indexed)
                        _FaqTile(index: index, entry: entry),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une question/réponse repliée par défaut — la liste reste scannable.
class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.index, required this.entry});

  final int index;
  final ({String question, String answer}) entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        key: Key('faq_tile_$index'),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          entry.question,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(entry.answer, style: theme.textTheme.bodyMedium)],
      ),
    );
  }
}

/// Source unique du contenu FAQ — l'ordre est l'ordre d'affichage.
const List<({String question, String answer})> _faqEntries = [
  (
    question: 'Qu\'est-ce que Baillan ?',
    answer:
        'Baillan est un outil de gestion locative pensé pour les bailleurs '
        'particuliers : registre de vos biens, locataires et baux, suivi des '
        'paiements et des dépenses, quittances de loyer conformes, '
        'régularisation des charges et simulateur d\'investissement. '
        'Sur le web comme sur mobile, avec les mêmes données.',
  ),
  (
    question: 'Baillan est-il gratuit ?',
    answer:
        'Oui, l\'application est gratuite à ce jour. Si une offre payante '
        'voit le jour, elle sera annoncée dans l\'application — vous ne '
        'serez jamais facturé sans action explicite de votre part.',
  ),
  (
    question: 'Puis-je essayer Baillan sans créer de compte ?',
    answer:
        'Oui. L\'« essai sans compte » ouvre le simulateur '
        'd\'investissement sans aucune inscription. Vos scénarios sont '
        'conservés 14 jours glissants ; si vous créez un compte pendant '
        'l\'essai, ils sont automatiquement rattachés à votre compte. '
        'Le registre complet (biens, baux, quittances) nécessite un compte.',
  ),
  (
    question: 'Les quittances générées sont-elles conformes à la loi ?',
    answer:
        'Les quittances portent les mentions requises par l\'article 21 de '
        'la loi n° 89-462 du 6 juillet 1989 : identité et adresse du '
        'bailleur, nom du locataire, adresse du logement, période, détail '
        'loyer et charges, montant total et date d\'émission. Elles sont '
        'numérotées, archivées dans l\'application et partageables en PDF.',
  ),
  (
    question: 'Comment fonctionne la régularisation des charges ?',
    answer:
        'Pour les baux en provisions sur charges, Baillan rapproche les '
        'provisions encaissées des dépenses récupérables enregistrées sur '
        'la période et calcule le solde (trop-perçu ou complément). Vous '
        'pouvez générer un avis de régularisation en PDF à transmettre au '
        'locataire. Les baux au forfait ne sont pas régularisables '
        '(le forfait est libératoire).',
  ),
  (
    question: 'Où sont stockées mes données et celles de mes locataires ?',
    answer:
        'Les données sont hébergées en Union européenne sur '
        'l\'infrastructure Google Firebase (Firestore multi-région eur3 : '
        'Belgique, Pays-Bas, Finlande). Chaque compte n\'accède qu\'à ses '
        'propres données (règles de sécurité vérifiées côté serveur), les '
        'échanges sont chiffrés (HTTPS) et aucun outil de tracking '
        'publicitaire n\'est intégré. Détails : Politique de '
        'confidentialité.',
  ),
  (
    question: 'Qui est responsable des données de mes locataires (RGPD) ?',
    answer:
        'En tant que bailleur, vous êtes responsable du traitement des '
        'données de vos locataires ; Baillan vous fournit l\'outil (Google '
        'Firebase agit en sous-traitant). Pensez à informer vos locataires '
        'de l\'utilisation d\'un outil de gestion — leurs droits d\'accès, '
        'de rectification et d\'effacement s\'exercent auprès de vous.',
  ),
  (
    question: 'Mes locataires ont-ils accès à Baillan ?',
    answer:
        'Non. Baillan est aujourd\'hui un outil réservé au bailleur : vos '
        'locataires n\'ont ni compte ni accès à vos données. Vous leur '
        'transmettez les documents (quittances, avis de régularisation) '
        'en PDF, par le canal de votre choix.',
  ),
  (
    question: 'Comment supprimer mon compte et mes données ?',
    answer:
        'Depuis l\'application : Profil → « Supprimer mon compte » '
        '(confirmation d\'identité requise), ou depuis la page publique '
        '/delete-account. La suppression est immédiate et définitive : '
        'biens, locataires, baux, paiements, documents, dépenses et '
        'simulations sont effacés. Seules les quittances émises sont '
        'conservées 5 ans (obligation légale de preuve), sous forme '
        'archivée inaccessible, puis supprimées.',
  ),
  (
    question: 'J\'ai oublié mon mot de passe, que faire ?',
    answer:
        'Sur l\'écran de connexion, cliquez « Mot de passe oublié ? » : un '
        'email de réinitialisation vous est envoyé. Si vous vous êtes '
        'inscrit avec Google ou Apple, connectez-vous simplement via le '
        'bouton correspondant — il n\'y a pas de mot de passe Baillan à '
        'retenir.',
  ),
  (
    question: 'Comment contacter le support ?',
    answer:
        'Une fois connecté : Profil → Aide → « Nous contacter ». Décrivez '
        'votre demande, nous vous répondons par email à l\'adresse de '
        'votre compte.',
  ),
];
